'use strict'

angular.module('swarmApp').factory 'Achievement', (util, $log, $rootScope, env) -> class Achievement
  constructor: (@game, @type) ->
    @name = @type.name
  _init: ->
    @game.session.achievements ?= {}
    @requires = _.map @type.requires, (require) =>
      require = _.clone require
      if require.unittype
        require.unit = util.assert @game.unit require.unittype
      if require.upgradetype
        require.upgrade = util.assert @game.upgrade require.upgradetype
      util.assert not (require.unit and require.upgrade), "achievement requirement can't have both unit and upgrade", @name
      return require

  isEarned: ->
    @game.session.achievements[@name]?

  earn: (elapsed=@game.elapsedStartMillis()) ->
    if env.achievementsEnabled
      if not @isEarned()
        @game.withSave =>
          @game.session.achievements[@name] = elapsed
        $rootScope.$emit 'achieve', this
      # emit even if already earned, while testing
      #$rootScope.$emit 'achieve', this

  earnedAtMillisElapsed: ->
    @game.session.achievements[@name]

  earnedAtMoment: ->
    if not @isEarned()?
      return undefined
    ret = moment @game.session.date.started
    ret.add @game.session.achievements[@name], 'ms'
    return ret

  pointsEarned: ->
    if @isEarned() then @type.points else 0

angular.module('swarmApp').factory 'AchievementTypes', (spreadsheetUtil, util, $log) -> class AchievementTypes
  constructor: ->
    @list = []
    @byName = {}

  register: (achievement) ->
    @list.push achievement
    @byName[achievement.name] = achievement

  pointsPossible: ->
    return util.sum _.map @list, (a) -> a.points

  @parseSpreadsheet: (data, unittypes) ->
    rows = spreadsheetUtil.parseRows {name:['requires']}, data.data.achievements.elements
    ret = new AchievementTypes()
    for row in rows
      ret.register row
    for row in ret.list
      spreadsheetUtil.resolveList row.requires, 'unittype', unittypes.byName, {required:false}
      util.assert row.points > 0, 'achievement must have points', row.name, row
      util.assert _.isNumber(row.points), 'achievement points must be number', row.name, row
    return ret

angular.module('swarmApp').factory 'AchievementsListener', (util, $log) -> class AchievementsListener
  constructor: (@game, @scope) ->
    @_listen @scope

  _listen: (@scope) ->
    for achieve in @game.achievementlist() then do (achieve) =>
      for require in achieve.requires
        if require.event and not require.unit then do (require) =>
          # trigger event once achievement
          if require.val
            require.val = JSON.parse require.val
            $log.debug 'parse event-achievement json', require.event, require.val
          cancelListen = @scope.$on require.event, (event, param) =>
            $log.debug 'achieve listen', require.event, param, require.val
            if require.val
              # very simple equality validation
              validparam = _.pick param, _.keys require.val
              valid = _.isEqual validparam, require.val
              $log.debug 'validate', require.event, require.val, validparam, valid
              if not valid
                return
            achieve.earn()
            # TODO rebuild this on reset
            #cancelListen()

    @scope.$on 'command', (event, cmd) =>
      $log.debug 'checking achievements for command', cmd
      if cmd.unitname?
        # TODO index these better, check on only the current unit
        for achieve in @game.achievementlist()
          for require in achieve.requires
            # unit count achievement
            if not require.event and require.unit and require.val
              # want to ignore generators, so use statistics-count
              # statistics are added before achievement-check, fortunately
              if require.unit.name == cmd.unitname
                count = require.unit.statistics().twinnum ? 0
                $log.debug 'achievement check: unitcount after command', require.unit.name, count, count? && count >= require.val
                if count? && count >= require.val
                  $log.debug 'earned', achieve.name, achieve
                  # requirements are 'or'ed
                  achieve.earn()
            if not require.event and require.upgrade and require.val
              # no upgrade-generators, so count() is safe
              count = require.upgrade.count()
              $log.debug 'achievement check: upgradecount after command', require.upgrade.name, count, count? && count >= require.val
              if count? && count >= require.val
                $log.debug 'earned', achieve.name, achieve
                # requirements are 'or'ed
                achieve.earn()

angular.module('swarmApp').factory 'achievementslistener', (AchievementsListener, game, $rootScope) ->
  new AchievementsListener game, $rootScope

###*
 # @ngdoc service
 # @name swarmApp.achievements
 # @description
 # # achievements
 # Factory in the swarmApp.
###
angular.module('swarmApp').factory 'achievements', (AchievementTypes, unittypes, spreadsheet) ->
  AchievementTypes.parseSpreadsheet spreadsheet, unittypes