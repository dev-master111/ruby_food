require 'open_food_network/enterprise_fee_calculator'
require 'open_food_network/distribution_change_validator'
require 'open_food_network/feature_toggle'
require 'open_food_network/tag_rule_applicator'

ActiveSupport::Notifications.subscribe('spree.order.contents_changed') do |name, start, finish, id, payload|
  payload[:order].reload.update_distribution_charge!
end

Spree::Order.class_eval do
  belongs_to :order_cycle
  belongs_to :distributor, :class_name => 'Enterprise'
  belongs_to :cart
  belongs_to :customer

  validates :customer, presence: true, if: :require_customer?
  validate :products_available_from_new_distribution, :if => lambda { distributor_id_changed? || order_cycle_id_changed? }
  attr_accessible :order_cycle_id, :distributor_id

  before_validation :shipping_address_from_distributor
  before_validation :associate_customer, unless: :customer_id?
  before_validation :ensure_customer, unless: :customer_is_valid?

  checkout_flow do
    go_to_state :address
    go_to_state :delivery
    go_to_state :payment, :if => lambda { |order|
      # Fix for #2191
      if order.shipping_method.andand.require_ship_address and
        if order.ship_address.andand.valid?
          order.create_shipment!
          order.update_totals
        end
      end
      order.payment_required?
    }
    go_to_state :confirm, :if => lambda { |order| order.confirmation_required? }
    go_to_state :complete, :if => lambda { |order| (order.payment_required? && order.has_unprocessed_payments?) || !order.payment_required? }
    remove_transition :from => :delivery, :to => :confirm
  end


  # -- Scopes
  scope :managed_by, lambda { |user|
    if user.has_spree_role?('admin')
      scoped
    else
      # Find orders that are distributed by the user or have products supplied by the user
      # WARNING: This only filters orders, you'll need to filter line items separately using LineItem.managed_by
      with_line_items_variants_and_products_outer.
      where('spree_orders.distributor_id IN (?) OR spree_products.supplier_id IN (?)', user.enterprises, user.enterprises).
      select('DISTINCT spree_orders.*')
    end
  }

  scope :distributed_by_user, lambda { |user|
    if user.has_spree_role?('admin')
      scoped
    else
      where('spree_orders.distributor_id IN (?)', user.enterprises)
    end
  }

  scope :with_line_items_variants_and_products_outer, lambda {
    joins('LEFT OUTER JOIN spree_line_items ON (spree_line_items.order_id = spree_orders.id)').
    joins('LEFT OUTER JOIN spree_variants ON (spree_variants.id = spree_line_items.variant_id)').
    joins('LEFT OUTER JOIN spree_products ON (spree_products.id = spree_variants.product_id)')
  }

  scope :not_state, lambda { |state|
    where("state != ?", state)
  }

  # -- Methods
  def products_available_from_new_distribution
    # Check that the line_items in the current order are available from a newly selected distribution
    errors.add(:base, "Distributor or order cycle cannot supply the products in your cart") unless DistributionChangeValidator.new(self).can_change_to_distribution?(distributor, order_cycle)
  end

  def empty_with_clear_shipping_and_payments!
    empty_without_clear_shipping_and_payments!
    payments.clear
    update_attributes(shipping_method_id: nil)
  end
  alias_method_chain :empty!, :clear_shipping_and_payments

  def set_order_cycle!(order_cycle)
    unless self.order_cycle == order_cycle
      self.order_cycle = order_cycle
      self.distributor = nil unless order_cycle.nil? || order_cycle.has_distributor?(distributor)
      self.empty!
      save!
    end
  end

  def remove_variant(variant)
    line_items(:reload)
    current_item = find_line_item_by_variant(variant)
    current_item.andand.destroy
  end


  # Overridden to support max_quantity
  def add_variant(variant, quantity = 1, max_quantity = nil, currency = nil)
    line_items(:reload)
    current_item = find_line_item_by_variant(variant)

    # Notify bugsnag if we get line items with a quantity of zero
    if quantity == 0
      Bugsnag.notify(RuntimeError.new("Zero Quantity Line Item"), {
        current_item: current_item.as_json,
        line_items: line_items.map(&:id),
        variant: variant.as_json
      })
    end

    if current_item
      current_item.quantity = quantity
      current_item.max_quantity = max_quantity

      # This is the original behaviour, behaviour above is so that we can resolve the order populator bug
      # current_item.quantity ||= 0
      # current_item.max_quantity ||= 0
      # current_item.quantity += quantity.to_i
      # current_item.max_quantity += max_quantity.to_i
      current_item.currency = currency unless currency.nil?
      current_item.save
    else
      current_item = Spree::LineItem.new(:quantity => quantity, max_quantity: max_quantity)
      current_item.variant = variant
      if currency
        current_item.currency = currency unless currency.nil?
        current_item.price    = variant.price_in(currency).amount
      else
        current_item.price    = variant.price
      end
      self.line_items << current_item
    end

    self.reload
    current_item
  end

  def cap_quantity_at_stock!
    line_items.each &:cap_quantity_at_stock!
  end


  def set_distributor!(distributor)
    self.distributor = distributor
    self.order_cycle = nil unless self.order_cycle.andand.has_distributor? distributor
    save!
  end

  def set_distribution!(distributor, order_cycle)
    self.distributor = distributor
    self.order_cycle = order_cycle
    save!
  end

  def update_distribution_charge!
    with_lock do
      EnterpriseFee.clear_all_adjustments_on_order self

      line_items.each do |line_item|
        if provided_by_order_cycle? line_item
          OpenFoodNetwork::EnterpriseFeeCalculator.new.create_line_item_adjustments_for line_item

        else
          pd = product_distribution_for line_item
          pd.create_adjustment_for line_item if pd
        end
      end

      if order_cycle
        OpenFoodNetwork::EnterpriseFeeCalculator.new.create_order_adjustments_for self
      end
    end
  end

  def set_variant_attributes(variant, attributes)
    line_item = find_line_item_by_variant(variant)

    if line_item
      if attributes.key?(:max_quantity) && attributes[:max_quantity].to_i < line_item.quantity
        attributes[:max_quantity] = line_item.quantity
      end

      line_item.assign_attributes(attributes)
      line_item.save!
    end
  end

  def line_item_variants
    line_items.map(&:variant)
  end

  def admin_and_handling_total
    adjustments.eligible.where("originator_type = ? AND source_type != ?", 'EnterpriseFee', 'Spree::LineItem').sum(&:amount)
  end

  def payment_fee
    adjustments.payment_fee.map(&:amount).sum
  end

  # Does this order have shipments that can be shipped?
  def ready_to_ship?
    self.shipments.any?{|s| s.can_ship?}
  end

  # Ship all pending orders
  def ship
    self.shipments.each do |s|
      s.ship if s.can_ship?
    end
  end

  def shipping_tax
    adjustments(:reload).shipping.sum &:included_tax
  end

  def enterprise_fee_tax
    adjustments(:reload).enterprise_fee.sum &:included_tax
  end

  def total_tax
    (adjustments + price_adjustments).sum &:included_tax
  end

  def account_invoice?
    distributor_id == Spree::Config.accounts_distributor_id
  end

  # Overrride of Spree method, that allows us to send separate confirmation emails to user and shop owners
  # And separately, to skip sending confirmation email completely for user invoice orders
  def deliver_order_confirmation_email
    unless account_invoice?
      Delayed::Job.enqueue ConfirmOrderJob.new(id)
    end
  end


  private

  def shipping_address_from_distributor
    if distributor
      # This method is confusing to conform to the vagaries of the multi-step checkout
      # We copy over the shipping address when we have no shipping method selected
      # We can refactor this when we drop the multi-step checkout option
      #
      if shipping_method.andand.require_ship_address == false
        self.ship_address = distributor.address.clone

        if bill_address
          self.ship_address.firstname = bill_address.firstname
          self.ship_address.lastname = bill_address.lastname
          self.ship_address.phone = bill_address.phone
        end
      end
    end
  end

  def provided_by_order_cycle?(line_item)
    order_cycle_variants = order_cycle.andand.variants || []
    order_cycle_variants.include? line_item.variant
  end

  def product_distribution_for(line_item)
    line_item.variant.product.product_distribution_for self.distributor
  end

  def require_customer?
    return true unless new_record? or state == 'cart'
  end

  def customer_is_valid?
    return true unless require_customer?
    customer.present? && customer.enterprise_id == distributor_id && customer.email == email_for_customer
  end

  def email_for_customer
    (user.andand.email || email).andand.downcase
  end

  def associate_customer
    return customer if customer.present?
    self.customer = Customer.of(distributor).find_by_email(email_for_customer)
  end

  def ensure_customer
    unless associate_customer
      customer_name = bill_address.andand.full_name
      self.customer = Customer.create(enterprise: distributor, email: email_for_customer, user: user, name: customer_name, bill_address: bill_address.andand.clone, ship_address: ship_address.andand.clone)
    end
  end
end
