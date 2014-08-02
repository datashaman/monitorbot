redis = require('redis')
EventEmitter = require('events').EventEmitter
DBWrapper = require('node-dbi').DBWrapper
yaml = require('js-yaml')
path = require('path')
fs = require('fs')

determineEnvironment = ->
    'local'

loadConfig = ->
    environment = determineEnvironment()
    yaml.safeLoad(fs.readFileSync(path.join('config', environment + '.yaml'), 'utf8'))

initDatabase = (name) ->
    unless databases[name]?
        databaseConfig = config.databases[name]
        databases[name] = new DBWrapper(databaseConfig.adapter, databaseConfig)
        databases[name].connect()
    databases[name]

checkThreshold = (value, compare, threshold) ->
    switch compare
        when 'GTE' then value >= threshold
        when 'LTE' then value <= threshold
        when 'GT' then value > threshold
        when 'LT' then value < threshold
        when 'NE' then value != threshold
        when 'EQ' then value == threshold
        else value > threshold

generateValue =
    database: (check, group, done) ->
        name = check.database or 'default'
        db = initDatabase(name)
        db.fetchOne check.query, [], (error, value) ->
            return done(error) if error?
            done(null, value)

getSecondsTimestamp = (ts=null) ->
    ts = new Date() if ts is null
    Math.floor(ts / 1000)

getRoundedTimestamp = (granularity, ts_seconds=null) ->
    ts_seconds = getSecondsTimestamp() if ts_seconds is null
    factor = granularity.size * granularity.factor
    Math.floor(ts_seconds  / factor) * factor

storeData = (key, data) ->
    ts_seconds = getSecondsTimestamp()
    for name, granularity of config.storage.granularities
        ts = getRoundedTimestamp(granularity, ts_seconds)
        tsKey = key + ':' + name + ':' + ts
        storage.hset tsKey, ts_seconds, JSON.stringify(data)
        storage.expireat tsKey, ts + granularity.ttl

checkGroup = (group) ->
    for check in group.checks
        func = generateValue[check.type]

        func check, group, (error, value) -> 
            return events.emit('error', error) if error?

            state = 'normal'

            if checkThreshold(value, check.compare, check.crit)
                state = 'critical'
                events.emit 'critical',
                    check: check
                    group: group
                    value: value

            else if checkThreshold(value, check.compare, check.warn)
                state = 'critical'
                events.emit 'warning',
                    check: check
                    group: group
                    value: value

            if check.storage?
                storeData check.storage,
                    state: state
                    value: value

events = new EventEmitter

databases = {}

config = loadConfig()

config.storage.redis ||=
    port: 6379
    host: 'localhost'
    options: {}

storage = redis.createClient(config.storage.redis.port or 6379, config.storage.redis.host or 'localhost', config.storage.redis.options or {})

module.exports = (robot) ->
    events.on 'warning', (stream) ->
        check = stream.check
        room = config.room or 'Shell'
        compare = check.compare or 'GT'
        robot.messageRoom room, '\nCheck ' + check.name + ' in group ' + stream.group.name + ' warning: ' + stream.value + ' ' + compare + ' ' + check.warn

    events.on 'critical', (stream) ->
        check = stream.check
        room = config.room or 'Shell'
        compare = check.compare or 'GT'
        robot.messageRoom room, '\nCheck ' + check.name + ' in group ' + stream.group.name + ' critical: ' + stream.value + ' ' + compare + ' ' + check.crit

    try
        fileNames = fs.readdirSync('groups-enabled')
        for fileName in fileNames
            unless fileName[0] == '.'
                group = yaml.safeLoad(fs.readFileSync(path.join('groups-enabled', fileName), 'utf8'))
                group.intervalObject = setInterval(checkGroup, group.interval * 1000, group)

    catch error
        console.log error
