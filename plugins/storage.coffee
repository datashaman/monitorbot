redis = require('redis')

module.exports = ->
    config = @getConfig()

    config.storage.redis ||=
        port: 6379
        host: 'localhost'
        options: {}

    storage = redis.createClient(config.storage.redis.port or 6379,
        config.storage.redis.host or 'localhost',
        config.storage.redis.options or {})

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

    @on 'checked', (stream) ->
        storeData(stream.check.storage, stream) if stream.check.storage?
