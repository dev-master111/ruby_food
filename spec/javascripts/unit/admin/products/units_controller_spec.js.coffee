describe "unitsCtrl", ->
  ctrl = null
  scope = null
  product = null

  beforeEach ->
    module('admin.products')
    inject ($rootScope, $controller, VariantUnitManager) ->
      scope = $rootScope
      ctrl = $controller 'unitsCtrl', {$scope: scope, VariantUnitManager: VariantUnitManager}

  describe "interpretting variant_unit_with_scale", ->
    it "splits string with one underscore and stores the two parts", ->
      scope.product.variant_unit_with_scale = "weight_1000"
      scope.processVariantUnitWithScale()
      expect(scope.product.variant_unit).toEqual "weight"
      expect(scope.product.variant_unit_scale).toEqual 1000

    it "interprets strings with no underscore as variant_unit", ->
      scope.product.variant_unit_with_scale = "items"
      scope.processVariantUnitWithScale()
      expect(scope.product.variant_unit).toEqual "items"
      expect(scope.product.variant_unit_scale).toEqual null

    it "sets variant_unit and variant_unit_scale to null", ->
      scope.product.variant_unit_with_scale = null
      scope.processVariantUnitWithScale()
      expect(scope.product.variant_unit).toEqual null
      expect(scope.product.variant_unit_scale).toEqual null

  describe "interpretting unit_value_with_description", ->
    beforeEach ->
      scope.product.master = {}

    describe "when a variant_unit_scale is present", ->
      beforeEach ->
        scope.product.variant_unit_scale = 1

      it "splits by whitespace in to unit_value and unit_description", ->
        scope.product.master.unit_value_with_description = "12 boxes"
        scope.processUnitValueWithDescription()
        expect(scope.product.master.unit_value).toEqual 12
        expect(scope.product.master.unit_description).toEqual "boxes"

      it "uses whole string as unit_value when only numerical characters are present", ->
        scope.product.master.unit_value_with_description = "12345"
        scope.processUnitValueWithDescription()
        expect(scope.product.master.unit_value).toEqual 12345
        expect(scope.product.master.unit_description).toEqual ''

      it "uses whole string as description when string does not start with a number", ->
        scope.product.master.unit_value_with_description = "boxes 12"
        scope.processUnitValueWithDescription()
        expect(scope.product.master.unit_value).toEqual null
        expect(scope.product.master.unit_description).toEqual "boxes 12"

      it "does not require whitespace to split unit value and description", ->
        scope.product.master.unit_value_with_description = "12boxes"
        scope.processUnitValueWithDescription()
        expect(scope.product.master.unit_value).toEqual 12
        expect(scope.product.master.unit_description).toEqual "boxes"

      it "once a whitespace occurs, all subsequent numerical characters are counted as description", ->
        scope.product.master.unit_value_with_description = "123 54 boxes"
        scope.processUnitValueWithDescription()
        expect(scope.product.master.unit_value).toEqual 123
        expect(scope.product.master.unit_description).toEqual "54 boxes"
