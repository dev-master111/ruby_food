Darkswarm.filter "printArrayOfObjects", ->
  (array, attr = 'name')->
    array ?= []
    array.map (a)->
      a[attr].toLowerCase()
    .join(", ")

Darkswarm.filter "printArray", ->
  (array)->
    array ?= []
    output = (item for item in array when item).join ", "
    output
    
