DBWrapper = require('node-dbi').DBWrapper
databases = {}

module.exports = ->
    config = @getConfig()

    initDatabase = (name) ->
        unless databases[name]?
            databaseConfig = config.databases[name]
            databases[name] = new DBWrapper(databaseConfig.adapter, databaseConfig)
            databases[name].connect()
        databases[name]

    (check, group, done) ->
        name = check.database or 'default'
        db = initDatabase(name)
        db.fetchOne check.query, [], done
