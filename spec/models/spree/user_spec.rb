describe Spree.user_class do
  include AuthenticationWorkflow

  describe "associations" do
    it { should have_many(:owned_enterprises) }

    describe "addresses" do
      let(:user) { create(:user, bill_address: create(:address)) }

      it 'updates billing address with new address' do
        old_bill_address = user.bill_address
        new_bill_address = create(:address, firstname: 'abc')

        user.update_attributes(bill_address_attributes: new_bill_address.clone.attributes.merge('id' => old_bill_address.id))

        expect(user.bill_address.id).to eq old_bill_address.id
        expect(user.bill_address.firstname).to eq new_bill_address.firstname
      end

      it 'creates new shipping address' do
        new_ship_address = create(:address, firstname: 'abc')

        user.update_attributes(ship_address_attributes: new_ship_address.clone.attributes)

        expect(user.ship_address.id).not_to eq new_ship_address.id
        expect(user.ship_address.firstname).to eq new_ship_address.firstname
      end
    end

    describe "enterprise ownership" do
      let(:u1) { create(:user, enterprise_limit: 2) }
      let(:u2) { create(:user, enterprise_limit: 1) }
      let!(:e1) { create(:enterprise, owner: u1) }
      let!(:e2) { create(:enterprise, owner: u1) }

      it "provides access to owned enterprises" do
        expect(u1.owned_enterprises(:reload)).to include e1, e2
      end

      it "enforces the limit on the number of enterprise owned" do
        expect(u2.owned_enterprises(:reload)).to eq []
        u2.owned_enterprises << e1
        expect { u2.save! }.to_not raise_error
        expect do
          u2.owned_enterprises << e2
          u2.save!
        end.to raise_error ActiveRecord::RecordInvalid, "Validation failed: #{u2.email} is not permitted to own any more enterprises (limit is 1)."
      end
    end

    describe "group ownership" do
      let(:u1) { create(:user) }
      let(:u2) { create(:user) }
      let!(:g1) { create(:enterprise_group, owner: u1) }
      let!(:g2) { create(:enterprise_group, owner: u1) }
      let!(:g3) { create(:enterprise_group, owner: u2) }

      it "provides access to owned groups" do
        expect(u1.owned_groups(:reload)).to match_array([g1, g2])
        expect(u2.owned_groups(:reload)).to match_array([g3])
      end
    end

    it "loads a user's customer representation at a particular enterprise" do
      u = create(:user)
      e = create(:enterprise)
      c = create(:customer, user: u, enterprise: e)

      u.customer_of(e).should == c
    end
  end

  context "#create" do
    it "should send a signup email" do
      expect do
        create(:user)
      end.to enqueue_job ConfirmSignupJob
    end
  end

  describe "known_users" do
    let!(:u1) { create(:user) }
    let!(:u2) { create(:user) }
    let!(:u3) { create(:user) }
    let!(:e1) { create(:enterprise, owner: u1, users: [u1, u2]) }

    describe "as an enterprise user" do
      it "returns a list of users which manage shared enterprises" do
        expect(u1.known_users).to include u1, u2
        expect(u1.known_users).to_not include u3
        expect(u2.known_users).to include u1, u2
        expect(u2.known_users).to_not include u3
        expect(u3.known_users).to_not include u1, u2, u3
      end
    end

    describe "as admin" do
      let(:admin) { quick_login_as_admin }

      it "returns all users" do
        expect(admin.known_users).to include u1, u2, u3
      end
    end
  end

  describe "retrieving orders for /account page" do
    let!(:u1) { create(:user) }
    let!(:u2) { create(:user) }
    let!(:distributor1) { create(:distributor_enterprise) }
    let!(:distributor2) { create(:distributor_enterprise) }
    let!(:d1o1) { create(:completed_order_with_totals, distributor: distributor1, user_id: u1.id) }
    let!(:d1o2) { create(:completed_order_with_totals, distributor: distributor1, user_id: u1.id) }
    let!(:d1_order_for_u2) { create(:completed_order_with_totals, distributor: distributor1, user_id: u2.id) }
    let!(:d1o3) { create(:order, state: 'cart', distributor: distributor1, user_id: u1.id) }
    let!(:d2o1) { create(:completed_order_with_totals, distributor: distributor2, user_id: u2.id) }
    let!(:accounts_distributor) {create :distributor_enterprise}
    let!(:order_account_invoice) { create(:order, distributor: accounts_distributor, state: 'complete', user: u1) }

    let!(:completed_payment) { create(:payment, order: d1o1, state: 'completed') }
    let!(:payment) { create(:payment, order: d1o2, state: 'checkout') }

    before do
      Spree::Config.accounts_distributor_id = accounts_distributor.id
    end

    it "returns enterprises that the user has ordered from, excluding accounts distributor" do
      expect(u1.enterprises_ordered_from).to eq [distributor1.id]
    end

    it "returns orders and payments for the user, organised by distributor" do
      expect(u1.orders_by_distributor).to include distributor1
      expect(u1.orders_by_distributor.first.distributed_orders).to include d1o1
    end

    it "doesn't return irrelevant distributors" do
      expect(u1.orders_by_distributor).not_to include distributor2
    end
    it "doesn't return other users' orders" do
      expect(u1.orders_by_distributor.first.distributed_orders).not_to include d1_order_for_u2
    end

    it "doesn't return uncompleted orders" do
      expect(u1.orders_by_distributor.first.distributed_orders).not_to include d1o3
    end

    it "doesn't return payments that are still at checkout stage" do
      expect(u1.orders_by_distributor.first.distributed_orders.map{|o| o.payments}.flatten).not_to include payment
    end
  end
end
