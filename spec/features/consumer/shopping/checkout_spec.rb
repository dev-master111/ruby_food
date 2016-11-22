require 'spec_helper'


feature "As a consumer I want to check out my cart", js: true do
  include AuthenticationWorkflow
  include ShopWorkflow
  include CheckoutWorkflow
  include WebHelper
  include UIComponentHelper

  let!(:zone) { create(:zone_with_member) }
  let(:distributor) { create(:distributor_enterprise, charges_sales_tax: true) }
  let(:supplier) { create(:supplier_enterprise) }
  let!(:order_cycle) { create(:simple_order_cycle, suppliers: [supplier], distributors: [distributor], coordinator: create(:distributor_enterprise), variants: [variant]) }
  let(:enterprise_fee) { create(:enterprise_fee, amount: 1.23, tax_category: product.tax_category) }
  let(:product) { create(:taxed_product, supplier: supplier, price: 10, zone: zone, tax_rate_amount: 0.1) }
  let(:variant) { product.variants.first }
  let(:order) { create(:order, order_cycle: order_cycle, distributor: distributor) }

  before do
    Spree::Config.shipment_inc_vat = true
    Spree::Config.shipping_tax_rate = 0.25

    add_enterprise_fee enterprise_fee
    set_order order
    add_product_to_cart order, product
  end

  describe "with shipping and payment methods" do
    let(:sm1) { create(:shipping_method, require_ship_address: true, name: "Frogs", description: "yellow", calculator: Spree::Calculator::FlatRate.new(preferred_amount: 0.00)) }
    let(:sm2) { create(:shipping_method, require_ship_address: false, name: "Donkeys", description: "blue", calculator: Spree::Calculator::FlatRate.new(preferred_amount: 4.56)) }
    let(:sm3) { create(:shipping_method, require_ship_address: false, name: "Local", tag_list: "local") }
    let!(:pm1) { create(:payment_method, distributors: [distributor], name: "Roger rabbit", type: "Spree::PaymentMethod::Check") }
    let!(:pm2) { create(:payment_method, distributors: [distributor]) }
    let!(:pm3) do
      Spree::Gateway::PayPalExpress.create!(name: "Paypal", environment: 'test', distributor_ids: [distributor.id]).tap do |pm|
        pm.preferred_login = 'devnull-facilitator_api1.rohanmitchell.com'
        pm.preferred_password = '1406163716'
        pm.preferred_signature = 'AFcWxV21C7fd0v3bYYYRCpSSRl31AaTntNJ-AjvUJkWf4dgJIvcLsf1V'
      end
    end

    before do
      distributor.shipping_methods << sm1
      distributor.shipping_methods << sm2
      distributor.shipping_methods << sm3
    end

    describe "when I have an out of stock product in my cart" do
      before do
        Spree::Config.set allow_backorders: false
        variant.on_hand = 0
        variant.save!
      end

      it "returns me to the cart with an error message" do
        visit checkout_path

        page.should_not have_selector 'closing', text: "Checkout now"
        page.should have_selector 'closing', text: "Your shopping cart"
        page.should have_content "An item in your cart has become unavailable"
      end
    end
    context 'login in as user' do
      let(:user) { create(:user) }

      before do
        quick_login_as(user)
        visit checkout_path

        toggle_shipping
        choose sm1.name
        toggle_payment
        choose pm1.name
        toggle_details
        within "#details" do
          fill_in "First Name", with: "Will"
          fill_in "Last Name", with: "Marshall"
          fill_in "Email", with: "test@test.com"
          fill_in "Phone", with: "0468363090"
        end
        toggle_billing
        check "Save as default billing address"
        within "#billing" do
          fill_in "City", with: "Melbourne"
          fill_in "Postcode", with: "3066"
          fill_in "Address", with: "123 Your Head"
          select "Australia", from: "Country"
          select "Victoria", from: "State"
        end

        toggle_shipping
        check "Shipping address same as billing address?"
        check "Save as default shipping address"
      end

      it "sets user's default billing address and shipping address" do
        user.bill_address.should be_nil
        user.ship_address.should be_nil

        order.bill_address.should be_nil
        order.ship_address.should be_nil

        place_order
        page.should have_content "Your order has been processed successfully"

        order.reload.bill_address.address1.should eq '123 Your Head'
        order.reload.ship_address.address1.should eq '123 Your Head'

        order.customer.bill_address.address1.should eq '123 Your Head'
        order.customer.ship_address.address1.should eq '123 Your Head'

        user.reload.bill_address.address1.should eq '123 Your Head'
        user.reload.ship_address.address1.should eq '123 Your Head'
      end
    end

    context "on the checkout page" do
      before do
        visit checkout_path
        checkout_as_guest
      end

      it "shows the current distributor" do
        visit checkout_path
        page.should have_content distributor.name
      end

      it 'does not show the save as defalut address checkbox' do
        page.should_not have_content "Save as default billing address"
        page.should_not have_content "Save as default shipping address"
      end

      it "shows a breakdown of the order price" do
        toggle_shipping
        choose sm2.name

        page.should have_selector 'orderdetails .cart-total', text: "$11.23"
        page.should have_selector 'orderdetails .shipping', text: "$4.56"
        page.should have_selector 'orderdetails .total', text: "$15.79"

        # Tax should not be displayed in checkout, as the customer's choice of shipping method
        # affects the tax and we haven't written code to live-update the tax amount when they
        # make a change.
        page.should_not have_content product.tax_category.name
      end

      it "shows all shipping methods" do
        toggle_shipping
        page.should have_content "Frogs"
        page.should have_content "Donkeys"
        page.should have_content "Local"
      end

      context "when shipping method requires an address" do
        before do
          toggle_shipping
          choose sm1.name
        end
        it "shows ship address forms when 'same as billing address' is unchecked" do
          uncheck "Shipping address same as billing address?"
          find("#ship_address > div.visible").visible?.should be_true
        end
      end

      context "using FilterShippingMethods" do
        let(:user) { create(:user) }
        let(:customer) { create(:customer, user: user, enterprise: distributor) }

        it "shows shipping methods allowed by the rule" do
          # No rules in effect
          toggle_shipping
          page.should have_content "Frogs"
          page.should have_content "Donkeys"
          page.should have_content "Local"

          create(:filter_shipping_methods_tag_rule,
            enterprise: distributor,
            preferred_customer_tags: "local",
            preferred_shipping_method_tags: "local",
            preferred_matched_shipping_methods_visibility: 'visible')
            create(:filter_shipping_methods_tag_rule,
              enterprise: distributor,
              is_default: true,
              preferred_shipping_method_tags: "local",
              preferred_matched_shipping_methods_visibility: 'hidden')
          visit checkout_path
          checkout_as_guest

          # Default rule in effect, disallows access to 'Local'
          page.should have_content "Frogs"
          page.should have_content "Donkeys"
          page.should_not have_content "Local"

          quick_login_as(user)
          visit checkout_path

          # Default rule in still effect, disallows access to 'Local'
          page.should have_content "Frogs"
          page.should have_content "Donkeys"
          page.should_not have_content "Local"

          customer.update_attribute(:tag_list, "local")
          visit checkout_path

          # #local Customer can access 'Local' shipping method
          page.should have_content "Frogs"
          page.should have_content "Donkeys"
          page.should have_content "Local"
        end
      end
    end

    context "on the checkout page with payments open" do
      before do
        visit checkout_path
        checkout_as_guest
        toggle_payment
      end

      it "shows all available payment methods" do
        page.should have_content pm1.name
        page.should have_content pm2.name
        page.should have_content pm3.name
      end

      describe "purchasing" do
        it "takes us to the order confirmation page when we submit a complete form" do
          toggle_details
          within "#details" do
            fill_in "First Name", with: "Will"
            fill_in "Last Name", with: "Marshall"
            fill_in "Email", with: "test@test.com"
            fill_in "Phone", with: "0468363090"
          end
          toggle_billing
          within "#billing" do
            fill_in "Address", with: "123 Your Face"
            select "Australia", from: "Country"
            select "Victoria", from: "State"
            fill_in "City", with: "Melbourne"
            fill_in "Postcode", with: "3066"
          end
          toggle_shipping
          within "#shipping" do
            choose sm2.name
            fill_in 'Any comments or special instructions?', with: "SpEcIaL NoTeS"
          end
          toggle_payment
          within "#payment" do
            choose pm1.name
          end

          expect do
            place_order
            page.should have_content "Your order has been processed successfully"
          end.to enqueue_job ConfirmOrderJob

          # And the order's special instructions should be set
          o = Spree::Order.complete.first
          expect(o.special_instructions).to eq "SpEcIaL NoTeS"

          # And the Spree tax summary should not be displayed
          page.should_not have_content product.tax_category.name

          # And the total tax for the order, including shipping and fee tax, should be displayed
          # product tax    ($10.00 @ 10% = $0.91)
          # + fee tax      ($ 1.23 @ 10% = $0.11)
          # + shipping tax ($ 4.56 @ 25% = $0.91)
          #                              = $1.93
          page.should have_content "(includes tax)"
          page.should have_content "$1.93"
        end

        context "with basic details filled" do
          before do
            toggle_shipping
            choose sm1.name
            toggle_payment
            choose pm1.name
            toggle_details
            within "#details" do
              fill_in "First Name", with: "Will"
              fill_in "Last Name", with: "Marshall"
              fill_in "Email", with: "test@test.com"
              fill_in "Phone", with: "0468363090"
            end
            toggle_billing
            within "#billing" do
              fill_in "City", with: "Melbourne"
              fill_in "Postcode", with: "3066"
              fill_in "Address", with: "123 Your Face"
              select "Australia", from: "Country"
              select "Victoria", from: "State"
            end
            toggle_shipping
            check "Shipping address same as billing address?"
          end

          it "takes us to the order confirmation page when submitted with 'same as billing address' checked" do
            place_order
            page.should have_content "Your order has been processed successfully"
          end

          it "takes us to the cart page with an error when a product becomes out of stock just before we purchase", js: true do
            Spree::Config.set allow_backorders: false
            variant.on_hand = 0
            variant.save!

            place_order

            page.should_not have_content "Your order has been processed successfully"
            page.should have_selector 'closing', text: "Your shopping cart"
            page.should have_content "Out of Stock"
          end

          context "when we are charged a shipping fee" do
            before { choose sm2.name }

            it "creates a payment for the full amount inclusive of shipping" do
              place_order
              page.should have_content "Your order has been processed successfully"

              # There are two orders - our order and our new cart
              o = Spree::Order.complete.first
              o.adjustments.shipping.first.amount.should == 4.56
              o.payments.first.amount.should == 10 + 1.23 + 4.56 # items + fees + shipping
            end
          end

          context "with a credit card payment method" do
            let!(:pm1) { create(:payment_method, distributors: [distributor], name: "Roger rabbit", type: "Spree::Gateway::Bogus") }

            it "takes us to the order confirmation page when submitted with a valid credit card" do
              toggle_payment
              fill_in 'Card Number', with: "4111111111111111"
              select 'February', from: 'secrets.card_month'
              select (Date.current.year+1).to_s, from: 'secrets.card_year'
              fill_in 'Security Code', with: '123'

              place_order
              page.should have_content "Your order has been processed successfully"

              # Order should have a payment with the correct amount
              o = Spree::Order.complete.first
              o.payments.first.amount.should == 11.23
            end

            it "shows the payment processing failed message when submitted with an invalid credit card" do
              toggle_payment
              fill_in 'Card Number', with: "9999999988887777"
              select 'February', from: 'secrets.card_month'
              select (Date.current.year+1).to_s, from: 'secrets.card_year'
              fill_in 'Security Code', with: '123'

              place_order
              page.should have_content "Payment could not be processed, please check the details you entered"

              # Does not show duplicate shipping fee
              visit checkout_path
              page.should have_selector "th", text: "Shipping", count: 1
            end
          end
        end
      end
    end

    context "when the customer has a pre-set shipping and billing address" do
      before do
        # Load up the customer's order and give them a shipping and billing address
        # This is equivalent to when the customer has ordered before and their addresses
        # are pre-populated.
        o = Spree::Order.last
        o.ship_address = build(:address)
        o.bill_address = build(:address)
        o.save!
      end

      it "checks out successfully" do
        visit checkout_path
        checkout_as_guest
        choose sm2.name
        toggle_payment
        choose pm1.name

        expect do
          place_order
          page.should have_content "Your order has been processed successfully"
        end.to enqueue_job ConfirmOrderJob
      end
    end
  end
end
