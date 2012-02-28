Field = require './Field'

# TODO Do JSON OT
# TODO Offline support for OT

module.exports =
  type: 'Model'

  static:
    OT_MUTATOR: OT_MUTATOR = 'mutator,otMutator'

  events:
    init: (model) ->
      model.otFields = {}

      # TODO: Get rid of mutator post events like this
      model.on 'setPost', ([path, value], ver) ->
        # ver will be null for speculative values, so this detects
        # when the OT path has been created on the server
        if ver && value && value.$ot
          model._otField(path).specTrigger true

    bundle: (model) ->
      # TODO: toJSON shouldn't be called manually like this
      fields = {}
      for path, field of @otFields
        # OT objects aren't serializable until after one or more OT operations
        # have occured on that object
        fields[path] = field.toJSON()  if field.toJSON
      model._onLoad.push ['_loadOt', fields]

    socket: (model, socket) ->
      otFields = @otFields
      memory = @_memory
      model = this
      # OT callbacks
      socket.on 'otOp', ({path, op, v}) ->
        unless field = otFields[path]
          field = otFields[path] = new Field model, path
          field.specTrigger().on ->
            val = memory.get path, model._specModel()
            field.snapshot = val?.$ot || ''
            field.onRemoteOp op, v
        else
          field.onRemoteOp op, v

  proto:

    # TODO: Don't override standard get like this
    get:
      type: 'accessor'
      fn: (path) ->
        if at = @_at
          path = if path then at + '.' + path else at
        val = @_memory.get path, @_specModel()
        if val && val.$ot?
          return @_otField(path, val).snapshot
        return val

    insertOT:
      type: OT_MUTATOR
      fn: (path, pos, text, callback) ->
        op = [ { p: pos, i: text } ]
        @_otField(path).submitOp op, callback
        return

    delOT:
      type: OT_MUTATOR
      fn: (path, pos, len, callback) ->
        field = @_otField path
        del = field.snapshot.substr pos, len
        op = [ { p: pos, d: del } ]
        field.submitOp op, callback
        return del

    _loadOt: (fields) ->
      for path, json of fields
        @otFields[path] = Field.fromJSON json, this

    ot: (initVal) -> $ot: initVal || ''

    isOtPath: (path) ->
      @_memory.get(path, @_specModel()).$ot isnt undefined

    isOtVal: (val) -> !!(val && val.$ot)

    _otField: (path, val) ->
      path = @dereference path
      return field if field = @otFields[path]
      field = @otFields[path] = new Field this, path
      val ||= @_memory.get path, @_specModel()
      field.snapshot = val && val.$ot || ''
      # TODO field.remoteSnapshot snapshot
      return field
