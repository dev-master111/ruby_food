window.FieldsetMixin = ($scope)->
  $scope.next = (event = false)->
    event.preventDefault() if event
    $scope.show $scope.nextPanel

  $scope.onTimeout = ->
    if $scope[$scope.name].$valid
      $scope.next()

  $scope.valid = ->
    $scope.form().$valid

  $scope.form = ->
    $scope[$scope.name]

  $scope.field = (path)->
    $scope.form()[path]

  $scope.fieldValid = (path)->
    not ($scope.dirty(path) and $scope.invalid(path))

  $scope.dirty = (name)->
    $scope.field(name).$dirty || $scope.submitted

  $scope.invalid = (name)->
    $scope.field(name).$invalid

  $scope.error = (name)->
    $scope.field(name).$error

  $scope.fieldErrors = (path)->
    errors = for error, invalid of $scope.error(path)
      if invalid
        switch error
          when "required" then t('error_required')
          when "number"   then t('error_number')
          when "email"    then t('error_email')

    #server_errors = $scope.Order.errors[path.replace('order.', '')]
    #errors.push server_errors if server_errors?
    (errors.filter (error) -> error?).join ", "
