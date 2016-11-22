require 'open_food_network/user_balance_calculator'

module OpenFoodNetwork
  class OrderCycleManagementReport
    attr_reader :params
    def initialize(user, params = {})
      @params = params
      @user = user
    end

    def header
      if is_payment_methods?
        ["First Name", "Last Name", "Hub", "Hub Code", "Email", "Phone", "Shipping Method", "Payment Method", "Amount", "Balance"]
      else
        ["First Name", "Last Name", "Hub", "Hub Code", "Delivery Address", "Delivery Postcode", "Phone", "Shipping Method", "Payment Method", "Amount", "Balance", "Temp Controlled Items?", "Special Instructions"]
      end
    end

    def search
      Spree::Order.complete.where("spree_orders.state != ?", :canceled).distributed_by_user(@user).managed_by(@user).search(params[:q])
    end

    def orders
      filter search.result
    end

    def table_items
      if is_payment_methods?
        orders.map { |o| payment_method_row o }
      else
        orders.map { |o| delivery_row o }
      end
    end

    def filter(search_result)
      filter_to_payment_method filter_to_shipping_method filter_to_order_cycle search_result
    end

    private

    def payment_method_row(order)
      ba = order.billing_address
      da = order.distributor.andand.address
      [ba.firstname,
       ba.lastname,
       order.distributor.andand.name,
       customer_code(order.email),
       order.email,
       ba.phone,
       order.shipping_method.andand.name,
       order.payments.first.andand.payment_method.andand.name,
       order.payments.first.amount,
       OpenFoodNetwork::UserBalanceCalculator.new(order.email, order.distributor).balance
      ]
    end

    def delivery_row(order)
      sa = order.shipping_address
      da = order.distributor.andand.address
      [sa.firstname,
       sa.lastname,
       order.distributor.andand.name,
       customer_code(order.email),
       "#{sa.address1} #{sa.address2} #{sa.city}",
       sa.zipcode,
       sa.phone,
       order.shipping_method.andand.name,
       order.payments.first.andand.payment_method.andand.name,
       order.payments.first.amount,
       OpenFoodNetwork::UserBalanceCalculator.new(order.email, order.distributor).balance,
       has_temperature_controlled_items?(order),
       order.special_instructions
      ]
    end

    def filter_to_payment_method(orders)
      if params[:payment_method_in].present?
        orders.joins(payments: :payment_method).where(spree_payments: { payment_method_id: params[:payment_method_in]})
      else
        orders
      end
    end

    def filter_to_shipping_method(orders)
      if params[:shipping_method_in].present?
        orders.joins(:shipping_method).where(shipping_method_id: params[:shipping_method_in])
      else
        orders
      end
    end

    def filter_to_order_cycle(orders)
      if params[:order_cycle_id].present?
        orders.where(order_cycle_id: params[:order_cycle_id])
      else
        orders
      end
    end

    def has_temperature_controlled_items?(order)
      order.line_items.any? { |line_item| line_item.product.shipping_category.andand.temperature_controlled }
    end

    def is_payment_methods?
      params[:report_type] == "payment_methods"
    end

    def customer_code(email)
      customer = Customer.where(email: email).first
      customer.nil? ? "" : customer.code
    end
  end
end
