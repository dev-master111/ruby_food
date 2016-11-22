module OpenFoodNetwork
  class EnterpriseInjectionData
    def active_distributors
      @active_distributors ||= Enterprise.distributors_with_active_order_cycles
    end

    def earliest_closing_times
      @earliest_closing_times ||= OrderCycle.earliest_closing_times
    end

    def shipping_method_services
      @shipping_method_services ||= Spree::ShippingMethod.services
    end

    def relatives
      @relatives ||= EnterpriseRelationship.relatives(true)
    end

    def supplied_taxons
      @supplied_taxons ||= Spree::Taxon.supplied_taxons
    end

    def distributed_taxons
      @distributed_taxons ||= Spree::Taxon.distributed_taxons
    end
  end
end
