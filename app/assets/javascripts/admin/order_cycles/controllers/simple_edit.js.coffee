angular.module('admin.orderCycles').controller "AdminSimpleEditOrderCycleCtrl", ($scope, $location, $window, OrderCycle, Enterprise, EnterpriseFee, StatusMessage) ->
  $scope.orderCycleId = ->
    $location.absUrl().match(/\/admin\/order_cycles\/(\d+)/)[1]

  $scope.StatusMessage = StatusMessage
  $scope.enterprises = Enterprise.index(order_cycle_id: $scope.orderCycleId())
  $scope.enterprise_fees = EnterpriseFee.index(order_cycle_id: $scope.orderCycleId())
  $scope.OrderCycle = OrderCycle
  $scope.order_cycle = OrderCycle.load $scope.orderCycleId(), (order_cycle) =>
    $scope.init()

  $scope.$watch 'order_cycle_form.$dirty', (newValue) ->
      StatusMessage.display 'notice', 'You have unsaved changes' if newValue

  $scope.loaded = ->
    Enterprise.loaded && EnterpriseFee.loaded && OrderCycle.loaded

  $scope.init = ->
    $scope.outgoing_exchange = OrderCycle.order_cycle.outgoing_exchanges[0]

  $scope.enterpriseFeesForEnterprise = (enterprise_id) ->
    EnterpriseFee.forEnterprise(parseInt(enterprise_id))

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

  $scope.submit = ($event, destination) ->
    $event.preventDefault()
    StatusMessage.display 'progress', "Saving..."
    OrderCycle.mirrorIncomingToOutgoingProducts()
    OrderCycle.update(destination, $scope.order_cycle_form)

  $scope.cancel = (destination) ->
    $window.location = destination
