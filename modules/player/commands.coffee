reload = require('require-reload')(require)
{ delay, parseTime } = Core.util
{ commands } = Core
PlaylistImport = reload './models/playlistImport'

class PlayerCommands
  constructor: (@playerModule)->
    { @hud, @util, @registerCommand } = @playerModule
    { @permissions } = Core

    # Play
    @registerCommand 'play', { aliases: ['p', 'request', 'add'] }, (m, args, d, player)=>
      # Check Voice Connection
      unless m.member.getVoiceChannel()
        return m.reply 'You must be in a voice channel to request songs.'
      # Check item limit
      if @util.checkItemCountLimit(player, m.member)
        return m.reply 'You have exceeded the limit of items in queue for this server.'
      # Process request
      try
        items = args.split('\n').map (item) =>
          i =
            url: item.split('|')[0].trim()
            filters: (item.split('|')[1] or '').trim()
          if item.match(/@\s?(\d+(:\d+)*)/)
            i =
              time: parseTime(args.match(/@\s?(\d+(:\d+)*)/)[1])
              url: title.replace(/@\s?(\d+(:\d+)*)/, '').trim()
              filters: filters.replace(/@\s?(\d+(:\d+)*)/, '').trim()
          i
      catch e
        console.error e
        return m.reply(e.message) if e.message
      try
        # Single request
        if items.length is 1
          # Get Video Information
          info = await @util.getInfo(items[0].url)
          # Single video
          unless info.forEach
            info.startAt = items[0].time
            info.filters = items[0].filters
            if info.startAt > info.duration or info.startAt < 0
              return m.reply 'Invalid start time.'
              @util.processInfo(info, m, player)
          # Playlist
          else
            return m.reply('Only DJs can add playlists.') unless Core.permissions.isDJ(m.member)
            plImport = new PlaylistImport(m, info, items[0].filters, player)
            await plImport.import()
        # Multiple requests
        else
          unless Core.permissions.isDJ(m.member)
            return m.reply('Only DJs can request multiple videos at once.')
          plImport = new PlaylistImport(m, items, '', player)
          await plImport.import()
      catch e
        console.error e
        m.reply 'Something went wrong.', false, {
          color: 0xAA3300
          # Windows 10 installer flashbacks
          description: e.message.split('YouTube said:')[1] or 'Something went wrong.'
        }

    # Skip
    @registerCommand 'skip', (m, args, d, player)=>
      m.delete() if d.data.autoDel
      # Some checks
      return if m.author.bot
      unless player.queue._d.items.length or player.queue._d.nowPlaying
        return m.reply 'Nothing being played in this server.'
      # Instant skip for DJs and people who requested the current element
      if @permissions.isDJ(m.member) or m.author.id is player.queue._d.nowPlaying.requestedBy
        m.channel.sendMessage "**#{m.member.name}** skipped the current song."
        return player.skip()
      return m.reply 'You are not allowed to skip songs.' unless d.data.voteSkip
      # Vote skip if enabled
      commands.run('voteskip', m, args)

    @registerCommand 'voteskip', { aliases: ['vs'] }, (msg, args, d, player)=>
      msg.delete() if d.data.autoDel
      return msg.reply 'You are not allowed to skip songs.' unless d.data.voteSkip
      return msg.reply 'You must be in a voice channel.' unless msg.member.getVoiceChannel()
      unless player.queue.nowPlaying.voiceChannel is msg.member.getVoiceChannel()
        return msg.reply 'You must be in the same voice channel the bot is in.'
      if msg.author.id in player.queue.nowPlaying.voteSkip
        return msg.reply 'Did you really try to skip this song **again**?'
      # Democracy!
      # ~40% of channel members
      targetVotes = Math.round(player.queue.nowPlaying.voiceChannel.members.length * 0.4)
      player.queue._d.nowPlaying.voteSkip.push(msg.author.id)
      votes = player.queue._d.nowPlaying.voteSkip.length
      msg.channel.sendMessage """
      **#{msg.member.name}** voted to skip the current song (#{votes}/#{targetVotes})
      """

      if votes >= targetVotes
        msg.channel.sendMessage 'Skipping current song ~~with the power of democracy~~.'
        player.skip()

    # Clear / Stop
    @registerCommand 'clear', { aliases: ['stop'], djOnly: true }, (msg, a, d, player)=>
      player.stop()
      msg.channel.sendMessage 'Queue cleared.'

    # Pause
    @registerCommand 'pause', { djOnly: true }, (msg, a, d, player)=>
      try player.pause()
      catch e
        msg.reply e.message if e.message

    # Resume
    @registerCommand 'resume', { djOnly: true }, (msg, a , d, player)=>
      player.play()

    # Now Playing (np)
    @registerCommand 'np', {
      aliases: ['nowplaying', 'n'], ignoreFreeze: true
    }, (msg, a, d, player)=>
      return 'Nothing being played.' unless player.queue._d.nowPlaying
      m = await msg.channel.sendMessage(
        "Now playing in `#{player.queue.nowPlaying.voiceChannel.name}`:",
        false, await @hud.nowPlayingEmbed(player.queue.nowPlaying)
      )
      if d.data.autoDel
        msg.delete()
        await delay(15000)
        m.delete()

    # View Queue
    @registerCommand 'queue', { aliases: ['q'], ignoreFreeze: true }, (msg, args, d, player)=>
      return 'Nothing being played.' unless player.queue._d.nowPlaying
      m = await msg.channel.sendMessage await @hud.nowPlaying(player.queue.nowPlaying),
                                        false,
                                        @hud.queue(player.queue, parseInt(args) or 1)
      if d.data.autoDel
        msg.delete()
        await delay(30000)
        m.delete()

    # Shuffle
    @registerCommand 'shuffle', { djOnly: true }, (msg, a, d, player)=>
      return msg.channel.sendMessage 'The queue is empty.' unless player.queue._d.items.length
      player.queue.shuffle()
      msg.channel.sendMessage '✅'

    # Sauce
    @registerCommand 'sauce', {
      aliases: ['source', 'src'], ignoreFreeze: true
    }, (msg, args, d, player)=>
      return '¯\_(ツ)_/¯' unless player.queue._d.nowPlaying
      unless player.queue._d.nowPlaying.sauce
        return msg.reply 'Sorry, no sauce for the current item. :C'
      m = await msg.reply """
      Here's the sauce of the current item: #{player.queue._d.nowPlaying.sauce}
      """
      await delay(15000)
      m.delete() if d.data.autoDel

    # Remove Last / Undo
    @registerCommand 'removelast', { aliases: ['undo', 'rl'] }, (msg, args, d, player)=>
      return msg.channel.sendMessage 'The queue is empty.' unless player.queue._d.items.length
      commands.run('remove', msg, player.queue._d.items.length)

    # Remove
    @registerCommand 'remove', { aliases: ['rm'] }, (msg, args, d, player)=>
      index = (parseInt args) - 1
      itm = player.queue._d.items[index]
      unless itm
        return msg.channel.sendMessage "Can't find the specified item in the queue."
      unless itm.requestedBy is msg.author.id or @permissions.isDJ msg.member
        return msg.channel.sendMessage 'You can only remove your own items from the queue.'
      { item } = player.queue.remove(index, msg.member)
      msg.channel.sendMessage 'Removed from the queue:',
                              false,
                              @hud.removeItem(item, msg.member)

    # Swap
    @registerCommand 'swap', {
      aliases: ['sp'], djOnly: true, argSeparator: ' '
    }, (msg, args, d, player)=>
      return msg.channel.sendMessage 'Invalid arguments provided.' unless args.length is 2
      result = player.queue.swap(parseInt(args[0])-1, parseInt(args[1])-1, msg.member)
      return msg.reply 'Something went wrong' unless result
      msg.channel.sendMessage @hud.swapItems msg.member, result.items,
                              [result.index1, result.index2]

    # Move
    @registerCommand 'move', {
      aliases: ['mv'], djOnly: true, argSeparator: ' '
    }, (msg, args, d, player)=>
      return msg.channel.sendMessage 'Invalid arguments provided.' unless args.length is 2
      result = player.queue.move(parseInt(args[0])-1, parseInt(args[1])-1, msg.member)
      return msg.reply 'Something went wrong' unless result
      msg.channel.sendMessage @hud.moveItem msg.member, result.item,
                              [result.index, result.position]

    # Move to first place
    @registerCommand 'bump', { djOnly: true }, (msg, args, d, player)=>
      return msg.channel.sendMessage 'Invalid arguments provided.' unless parseInt(args) > 0
      result = player.queue.bump(parseInt(args)-1, msg.member)
      return msg.reply 'Something went wrong' unless result
      msg.channel.sendMessage @hud.moveItem msg.member, result.item,
                              [result.index, result.position]

    # Seek
    @registerCommand 'seek', { aliases: ['s'], djOnly: true }, (msg, args, d, player)=>
      try
        player.seek(parseTime(args))
      catch e
        msg.reply e.message if e.message

    # Update Filters
    @registerCommand 'fx', { aliases: ['|'] }, (msg, args, d, player)=>
      return unless @permissions.isDJ(msg.author, msg.guild) or
                    msg.author.id is player.queue._d.nowPlaying.requestedBy
      try
        filters = @util.parseFilters(args, msg.member, true)
        player.updateFilters(filters)
      catch e
        return msg.reply 'Something went wrong', false, {
          description: e.message or e,
          color: 0xFF0000
        }

    @registerCommand 'freeze', {
      djOnly: true, aliases: ['lock'], ignoreFreeze: true
    }, (msg, args, d, { queue })=>
      return 'Already frozen' if queue.frozen
      queue.frozen = true
      msg.reply '''
      The queue is now frozen. No changes can be made to the playlist unless you unfreeze it.
      '''

    @registerCommand 'unfreeze', {
      djOnly: true, aliases: ['unlock', 'thaw'], ignoreFreeze: true
    }, (msg, args, d, { queue })=>
      return 'Not frozen' unless queue.frozen
      queue.frozen = false
      msg.reply 'The queue is no longer frozen.'

module.exports = PlayerCommands
