module EnterprisesHelper
  def current_distributor
    @current_distributor ||= current_order(false).andand.distributor
  end

  def current_customer
    return nil unless spree_current_user && current_distributor
    @current_customer ||= spree_current_user.customer_of(current_distributor)
  end

  def available_shipping_methods
    return [] unless current_distributor.present?
    shipping_methods = current_distributor.shipping_methods

    applicator = OpenFoodNetwork::TagRuleApplicator.new(current_distributor, "FilterShippingMethods", current_customer.andand.tag_list)
    applicator.filter!(shipping_methods)

    shipping_methods.uniq
  end

  def available_payment_methods
    return [] unless current_distributor.present?
    payment_methods = current_distributor.payment_methods.available(:front_end).all

    applicator = OpenFoodNetwork::TagRuleApplicator.new(current_distributor, "FilterPaymentMethods", current_customer.andand.tag_list)
    applicator.filter!(payment_methods)

    payment_methods
  end

  def managed_enterprises
    Enterprise.managed_by(spree_current_user)
  end

  def enterprises_options enterprises
    enterprises.map { |enterprise| [enterprise.name + ": " + enterprise.address.address1 + ", " + enterprise.address.city, enterprise.id.to_i] }
  end

  def enterprises_to_names(enterprises)
    enterprises.map(&:name).sort.join(', ')
  end

  def enterprise_type_name(enterprise)
    if enterprise.sells == 'none'
      enterprise.producer_profile_only ? 'Profile' : 'Supplier Only'
    else
      "Has Shopfront"
    end
  end

  def enterprise_confirm_delete_message(enterprise)
    if enterprise.supplied_products.present?
      "This will also delete the #{pluralize enterprise.supplied_products.count, 'product'} that this enterprise supplies. Are you sure you want to continue?"
    else
      t(:are_you_sure)
    end
  end

  # Copied and modified from Spree's link_to_delete, which does not
  # allow customisation of the confirm message
  def link_to_delete_enterprise(enterprise)
    url = object_url(enterprise)
    name = t(:delete)
    options = {}
    options[:class] = "delete-resource"
    options[:data] = { :action => 'remove', :confirm => enterprise_confirm_delete_message(enterprise) }
    link_to_with_icon 'icon-trash', name, url, options
  end

  def shop_trial_in_progress?(enterprise)
    !!enterprise.shop_trial_start_date &&
    (enterprise.shop_trial_start_date + Spree::Config[:shop_trial_length_days].days > Time.zone.now) &&
    %w(own any).include?(enterprise.sells)
  end

  def shop_trial_expired?(enterprise)
    !!enterprise.shop_trial_start_date &&
    (enterprise.shop_trial_start_date + Spree::Config[:shop_trial_length_days].days <= Time.zone.now) &&
    %w(own any).include?(enterprise.sells)
  end

  def remaining_trial_days(enterprise)
    distance_of_time_in_words(Time.zone.now, enterprise.shop_trial_start_date + Spree::Config[:shop_trial_length_days].days)
  end
end
