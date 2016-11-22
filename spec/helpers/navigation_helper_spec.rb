require 'spec_helper'

module Spree
  module Admin
    describe NavigationHelper do
      describe "klass_for" do
        it "returns the class when present" do
          helper.klass_for('products').should == Spree::Product
        end

        it "returns a symbol when there's no available class" do
          helper.klass_for('reports').should == :report
        end

        it "returns :overview for the dashboard" do
          helper.klass_for('dashboard').should == :overview
        end

        it "returns Spree::Order for bulk_order_management" do
          helper.klass_for('bulk_order_management').should == Spree::Order
        end
      end
    end
  end
end
