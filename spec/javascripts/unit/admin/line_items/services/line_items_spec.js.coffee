describe "LineItems service", ->
  LineItems = LineItemResource = lineItems = $httpBackend = null

  beforeEach ->
    module 'admin.lineItems'

    jasmine.addMatchers
      toDeepEqual: (util, customEqualityTesters) ->
        compare: (actual, expected) ->
          { pass: angular.equals(actual, expected) }

    inject ($q, _$httpBackend_, _LineItems_, _LineItemResource_) ->
      LineItems = _LineItems_
      LineItemResource = _LineItemResource_
      $httpBackend = _$httpBackend_

  describe "#index", ->
    result = response = null

    beforeEach ->
      response = [{ id: 5, name: 'LineItem 1'}]
      $httpBackend.expectGET('/admin/line_items.json').respond 200, response
      result = LineItems.index()
      $httpBackend.flush()

    it "stores returned data in @lineItemsByID, with ids as keys", ->
      # LineItemResource returns instances of Resource rather than raw objects
      expect(LineItems.lineItemsByID).toDeepEqual { 5: response[0] }

    it "stores returned data in @pristineByID, with ids as keys", ->
      expect(LineItems.pristineByID).toDeepEqual { 5: response[0] }

    it "returns an array of line items", ->
      expect(result).toDeepEqual response


  describe "#save", ->
    describe "success", ->
      lineItem = null
      resolved = false

      beforeEach ->
        lineItem = new LineItemResource({ id: 15, order: { number: '12345678'} })
        $httpBackend.expectPUT('/admin/orders/12345678/line_items/15.json').respond 200, { id: 15, name: 'LineItem 1'}
        LineItems.save(lineItem).then( -> resolved = true)
        $httpBackend.flush()

      it "updates the pristine copy of the lineItem", ->
        # Resource results have extra properties ($then, $promise) that cause them to not
        # be exactly equal to the response object provided to the expectPUT clause above.
        expect(LineItems.pristineByID[15]).toEqual lineItem

      it "resolves the promise", ->
        expect(resolved).toBe(true);


    describe "failure", ->
      lineItem = null
      rejected = false

      beforeEach ->
        lineItem = new LineItemResource( { id: 15, order: { number: '12345678'} } )
        $httpBackend.expectPUT('/admin/orders/12345678/line_items/15.json').respond 422, { error: 'obj' }
        LineItems.save(lineItem).catch( -> rejected = true)
        $httpBackend.flush()

      it "does not update the pristine copy of the lineItem", ->
        expect(LineItems.pristineByID[15]).toBeUndefined()

      it "rejects the promise", ->
        expect(rejected).toBe(true);

  describe "#isSaved", ->
    describe "when attributes of the object have been altered", ->
      beforeEach ->
        spyOn(LineItems, "diff").and.returnValue ["attr1", "attr2"]

      it "returns false", ->
        expect(LineItems.isSaved({})).toBe false

    describe "when attributes of the object have not been altered", ->
      beforeEach ->
        spyOn(LineItems, "diff").and.returnValue []

      it "returns false", ->
        expect(LineItems.isSaved({})).toBe true


  describe "diff", ->
    beforeEach ->
      LineItems.pristineByID = { 23: { id: 23, price: 15, quantity: 3, something: 3 } }

    it "returns a list of properties that have been altered and are in the list of updateable attrs", ->
      expect(LineItems.diff({ id: 23, price: 12, quantity: 3 })).toEqual ["price"]
      expect(LineItems.diff({ id: 23, price: 15, something: 1 })).toEqual []


  describe "resetAttribute", ->
    lineItem = { id: 23, price: 15 }

    beforeEach ->
      LineItems.pristineByID = { 23: { id: 23, price: 12, quantity: 3 } }

    it "resets the specified value according to the pristine record", ->
      LineItems.resetAttribute(lineItem, "price")
      expect(lineItem.price).toEqual 12

  describe "#delete", ->
    describe "success", ->
      callback = jasmine.createSpy("callback")
      lineItem = null
      resolved = rejected = false

      beforeEach ->
        lineItem = new LineItemResource({ id: 15, order: { number: '12345678'} })
        LineItems.pristineByID[15] = lineItem
        LineItems.lineItemsByID[15] = lineItem
        $httpBackend.expectDELETE('/admin/orders/12345678/line_items/15.json').respond 200, { id: 15, name: 'LineItem 1'}
        LineItems.delete(lineItem, callback).then( -> resolved = true).catch( -> rejected = true)
        $httpBackend.flush()

      it "updates the pristine copy of the lineItem", ->
        expect(LineItems.pristineByID[15]).toBeUndefined()
        expect(LineItems.lineItemsByID[15]).toBeUndefined()

      it "runs the callback", ->
        expect(callback).toHaveBeenCalled()

      it "resolves the promise", ->
        expect(resolved).toBe(true)
        expect(rejected).toBe(false)


    describe "failure", ->
      callback = jasmine.createSpy("callback")
      lineItem = null
      resolved = rejected = false

      beforeEach ->
        lineItem = new LineItemResource({ id: 15, order: { number: '12345678'} })
        LineItems.pristineByID[15] = lineItem
        LineItems.lineItemsByID[15] = lineItem
        $httpBackend.expectDELETE('/admin/orders/12345678/line_items/15.json').respond 422, { error: 'obj' }
        LineItems.delete(lineItem, callback).then( -> resolved = true).catch( -> rejected = true)
        $httpBackend.flush()

      it "does not update the pristine copy of the lineItem", ->
        expect(LineItems.pristineByID[15]).toBeDefined()
        expect(LineItems.lineItemsByID[15]).toBeDefined()

      it "does not run the callback", ->
        expect(callback).not.toHaveBeenCalled()

      it "rejects the promise", ->
        expect(resolved).toBe(false)
        expect(rejected).toBe(true)
