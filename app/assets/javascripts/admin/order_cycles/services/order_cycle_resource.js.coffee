angular.module("admin.orderCycles").factory 'OrderCycleResource', ($resource) ->
  $resource('/admin/order_cycles/:id/:action.json', {}, {
    'index':
      method: 'GET'
      isArray: true
    'update':
      method: 'PUT'
  })
