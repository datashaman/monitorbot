EventEmitter = require('events').EventEmitter
yaml = require('js-yaml')
path = require('path')
fs = require('fs')

class Monitor extends EventEmitter
    constructor: ->
        @groups = []
        @plugins = require(path.resolve('plugins')).apply(@)
        @checks = require(path.resolve('checks')).apply(@)

    checkThreshold: (value, compare, threshold) ->
        switch compare
            when 'GTE' then value >= threshold
            when 'LTE' then value <= threshold
            when 'GT' then value > threshold
            when 'LT' then value < threshold
            when 'NE' then value != threshold
            when 'EQ' then value == threshold
            else value > threshold

    checkGroup: (group) ->
        for check in group.checks
            func = @checks[check.type]

            do (check, func) =>
                func check, group, (error, value) => 
                    return @emit('error', error) if error?

                    state = 'normal'

                    for level in ['critical', 'warning']
                        if @checkThreshold(value, check.compare, check[level])
                            state = level
                            @emit level,
                                check: check
                                group: group
                                value: value
                                state: state
                            break

                    @emit 'checked',
                        check: check
                        # JSON encoding doesn't like this (circular), resolve later
                        # group: group
                        value: value
                        state: state

    determineEnvironment: ->
        'local'

    getConfig: ->
        unless @config?
            environment = @determineEnvironment()
            @config = yaml.safeLoad(fs.readFileSync(path.resolve('config', environment + '.yaml'), 'utf8'))
        @config

    start: ->
        fileNames = fs.readdirSync(path.resolve('groups-enabled'))
        for fileName in fileNames
            unless fileName[0] == '.'
                group = yaml.safeLoad(fs.readFileSync(path.resolve('groups-enabled', fileName), 'utf8'))
                group.intervalObject = setInterval(((group) => @checkGroup(group)), group.interval * 1000, group)
                @groups.push(group)

    renderCheckStream: (level, stream) ->
        check = stream.check
        room = @getConfig().room or 'Shell'
        compare = check.compare or 'GT'
        level + ': ' + stream.group.name + ' / ' + check.name + ' : ' + stream.value + ' ' + compare + ' ' + check[level]

monitor = new Monitor

module.exports = (robot) ->
    config = monitor.getConfig()

    notifyOn = (level) ->
        monitor.on level, (stream) ->
            room = config.room or 'Shell'
            message = monitor.renderCheckStream(level, stream)
            robot.messageRoom room, '\n' + message

    notifyOn('warning')
    notifyOn('critical')

    monitor.start()
