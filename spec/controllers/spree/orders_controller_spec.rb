require 'spec_helper'

describe Spree::OrdersController do
  let(:distributor) { double(:distributor) }
  let(:order) { create(:order) }
  let(:order_cycle) { create(:simple_order_cycle) }

  it "redirects home when no distributor is selected" do
    spree_get :edit
    response.should redirect_to root_path
  end

  it "redirects to shop when order is empty" do
    controller.stub(:current_distributor).and_return(distributor)
    controller.stub(:current_order_cycle).and_return(order_cycle)
    controller.stub(:current_order).and_return order
    order.stub_chain(:line_items, :empty?).and_return true
    order.stub(:insufficient_stock_lines).and_return []
    session[:access_token] = order.token
    spree_get :edit
    response.should redirect_to shop_path
  end

  it "redirects to the shop when no order cycle is selected" do
    controller.stub(:current_distributor).and_return(distributor)
    spree_get :edit
    response.should redirect_to shop_path
  end

  it "redirects home with message if hub is not ready for checkout" do
    VariantOverride.stub(:indexed).and_return({})

    order = subject.current_order(true)
    distributor.stub(:ready_for_checkout?) { false }
    order.stub(distributor: distributor, order_cycle: order_cycle)

    order.should_receive(:empty!)
    order.should_receive(:set_distribution!).with(nil, nil)

    spree_get :edit

    response.should redirect_to root_url
    flash[:info].should == "The hub you have selected is temporarily closed for orders. Please try again later."
  end

  describe "when an item has insufficient stock" do
    let(:order) { subject.current_order(true) }
    let(:oc) { create(:simple_order_cycle, distributors: [d], variants: [variant]) }
    let(:d) { create(:distributor_enterprise, shipping_methods: [create(:shipping_method)], payment_methods: [create(:payment_method)]) }
    let(:variant) { create(:variant, on_demand: false, on_hand: 5) }
    let(:line_item) { order.line_items.last }

    before do
      Spree::Config.allow_backorders = false
      order.set_distribution! d, oc
      order.add_variant variant, 5
      variant.update_attributes! on_hand: 3
    end

    it "displays a flash message when we view the cart" do
      spree_get :edit
      expect(response.status).to eq 200
      flash[:error].should == "An item in your cart has become unavailable."
    end
  end

  describe "returning stock levels in JSON on success" do
    let(:product) { create(:simple_product) }

    it "returns stock levels as JSON" do
      controller.stub(:variant_ids_in) { [123] }
      controller.stub(:stock_levels) { 'my_stock_levels' }
      Spree::OrderPopulator.stub(:new).and_return(populator = double())
      populator.stub(:populate) { true }
      populator.stub(:variants_h) { {} }

      xhr :post, :populate, use_route: :spree, format: :json

      data = JSON.parse(response.body)
      data['stock_levels'].should == 'my_stock_levels'
    end

    describe "generating stock levels" do
      let!(:order) { create(:order) }
      let!(:li) { create(:line_item, order: order, variant: v, quantity: 2, max_quantity: 3) }
      let!(:v) { create(:variant, count_on_hand: 4) }
      let!(:v2) { create(:variant, count_on_hand: 2) }

      before do
        order.reload
        controller.stub(:current_order) { order }
      end

      it "returns a hash with variant id, quantity, max_quantity and stock on hand" do
        controller.stock_levels(order, [v.id]).should ==
          {v.id => {quantity: 2, max_quantity: 3, on_hand: 4}}
      end

      it "includes all line items, even when the variant_id is not specified" do
        controller.stock_levels(order, []).should ==
          {v.id => {quantity: 2, max_quantity: 3, on_hand: 4}}
      end

      it "includes an empty quantity entry for variants that aren't in the order" do
        controller.stock_levels(order, [v.id, v2.id]).should ==
          {v.id  => {quantity: 2, max_quantity: 3, on_hand: 4},
           v2.id => {quantity: 0, max_quantity: 0, on_hand: 2}}
      end

      describe "encoding Infinity" do
        let!(:v) { create(:variant, on_demand: true, count_on_hand: 0) }

        it "encodes Infinity as a large, finite integer" do
          controller.stock_levels(order, [v.id]).should ==
            {v.id => {quantity: 2, max_quantity: 3, on_hand: 2147483647}}
        end
      end
    end

    it "extracts variant ids from the populator" do
      variants_h = [{:variant_id=>"900", :quantity=>2, :max_quantity=>nil},
       {:variant_id=>"940", :quantity=>3, :max_quantity=>3}]

      controller.variant_ids_in(variants_h).should == [900, 940]
    end
  end

  context "adding a group buy product to the cart" do
    it "sets a variant attribute for the max quantity" do
      distributor_product = create(:distributor_enterprise)
      p = create(:product, :distributors => [distributor_product], :group_buy => true)

      order = subject.current_order(true)
      order.stub(:distributor) { distributor_product }
      order.should_receive(:set_variant_attributes).with(p.master, {'max_quantity' => '3'})
      controller.stub(:current_order).and_return(order)

      expect do
        spree_post :populate, :variants => {p.master.id => 1}, :variant_attributes => {p.master.id => {:max_quantity => 3}}
      end.to change(Spree::LineItem, :count).by(1)
    end

    it "returns HTTP success when successful" do
      Spree::OrderPopulator.stub(:new).and_return(populator = double())
      populator.stub(:populate) { true }
      populator.stub(:variants_h) { {} }
      xhr :post, :populate, use_route: :spree, format: :json
      response.status.should == 200
    end

    it "returns failure when unsuccessful" do
      Spree::OrderPopulator.stub(:new).and_return(populator = double())
      populator.stub(:populate).and_return false
      xhr :post, :populate, use_route: :spree, format: :json
      response.status.should == 412
    end

    it "tells populator to overwrite" do
      Spree::OrderPopulator.stub(:new).and_return(populator = double())
      populator.should_receive(:populate).with({}, true)
      xhr :post, :populate, use_route: :spree, format: :json
    end
  end

  describe "removing line items from cart" do
    describe "when I pass params that includes a line item no longer in our cart" do
      it "should silently ignore the missing line item" do
        order = subject.current_order(true)
        li = order.add_variant(create(:simple_product, on_hand: 110).variants.first)
        spree_get :update, order: { line_items_attributes: {
          "0" => {quantity: "0", id: "9999"},
          "1" => {quantity: "99", id: li.id}
        }}
        response.status.should == 302
        li.reload.quantity.should == 99
      end
    end

    it "filters line items that are missing from params" do
      order = subject.current_order(true)
      li = order.add_variant(create(:simple_product).master)

      attrs = {
        "0" => {quantity: "0", id: "9999"},
        "1" => {quantity: "99", id: li.id}
      }

      controller.remove_missing_line_items(attrs).should == {
        "1" => {quantity: "99", id: li.id}
      }
    end
  end


  private

  def num_items_in_cart
    Spree::Order.last.andand.line_items.andand.count || 0
  end
end
