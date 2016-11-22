angular.module("admin.utils").directive "ofnWithTip", ($sanitize)->
  link: (scope, element, attrs) ->
    element.attr('data-powertip', $sanitize(attrs.ofnWithTip))
    element.powerTip
      smartPlacement: true
      fadeInTime: 50
      fadeOutTime: 50
      intentPollInterval: 300
