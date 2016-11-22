angular.module('admin.orderCycles').controller "AdminSimpleCreateOrderCycleCtrl", ($scope, $window, OrderCycle, Enterprise, EnterpriseFee, StatusMessage, ocInstance) ->
  $scope.StatusMessage = StatusMessage
  $scope.OrderCycle = OrderCycle
  $scope.order_cycle = OrderCycle.new {coordinator_id: ocInstance.coordinator_id}, =>
    # TODO: make this a get method, which only fetches one enterprise
    $scope.enterprises = Enterprise.index {coordinator_id: ocInstance.coordinator_id}, (enterprises) =>
      $scope.init(enterprises)
    $scope.enterprise_fees = EnterpriseFee.index(coordinator_id: ocInstance.coordinator_id)

  $scope.$watch 'order_cycle_form.$dirty', (newValue) ->
      StatusMessage.display 'notice', 'You have unsaved changes' if newValue

  $scope.init = (enterprises) ->
    enterprise = enterprises[Object.keys(enterprises)[0]]
    OrderCycle.addSupplier enterprise.id
    OrderCycle.addDistributor enterprise.id
    $scope.outgoing_exchange = OrderCycle.order_cycle.outgoing_exchanges[0]

    # All variants start as checked
    OrderCycle.setExchangeVariants(OrderCycle.order_cycle.incoming_exchanges[0],
      Enterprise.suppliedVariants(enterprise.id), true)

    OrderCycle.order_cycle.coordinator_id = enterprise.id

  $scope.loaded = ->
    Enterprise.loaded && EnterpriseFee.loaded && OrderCycle.loaded

  $scope.removeDistributionOfVariant = angular.noop

  $scope.setExchangeVariants = (exchange, variants, selected) ->
    OrderCycle.setExchangeVariants(exchange, variants, selected)

  $scope.suppliedVariants = (enterprise_id) ->
    Enterprise.suppliedVariants(enterprise_id)

  $scope.addCoordinatorFee = ($event) ->
    $event.preventDefault()
    OrderCycle.addCoordinatorFee()

  $scope.removeCoordinatorFee = ($event, index) ->
    $event.preventDefault()
    OrderCycle.removeCoordinatorFee(index)

  $scope.enterpriseFeesForEnterprise = (enterprise_id) ->
    EnterpriseFee.forEnterprise(parseInt(enterprise_id))

  $scope.submit = ($event, destination) ->
    $event.preventDefault()
    StatusMessage.display 'progress', "Saving..."
    OrderCycle.mirrorIncomingToOutgoingProducts()
    OrderCycle.create(destination)

  $scope.cancel = (destination) ->
      $window.location = destination
