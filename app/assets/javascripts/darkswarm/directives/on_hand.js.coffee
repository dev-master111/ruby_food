Darkswarm.directive "ofnOnHand", ->
  restrict: 'A'
  require: "ngModel"

  link: (scope, elem, attr, ngModel) ->
    # In cases where this field gets its value from the HTML element rather than the model,
    # initialise the model with the HTML value.
    if scope.$eval(attr.ngModel) == undefined
      ngModel.$setViewValue elem.val()

    ngModel.$parsers.push (viewValue) ->
      on_hand = parseInt(attr.ofnOnHand)
      if parseInt(viewValue) > on_hand
        alert t('insufficient_stock', {on_hand: on_hand})
        viewValue = on_hand
        ngModel.$setViewValue viewValue
        ngModel.$render()

      viewValue
