
exec = require("child_process").exec
argv = require("minimist")(process.argv.slice 2)
colors = require "colors"
async = require "async"

config = 
  local:
    rootBranch: "master"
  remote:
    repository: "origin"
    rootBranch: "master"
  install:
    url: "https://raw.github.com/xthom/gitf/latest/bin/install"

git = (cmd, cb) ->
  exec "git #{cmd}", cwd: process.cwd(), (err, stdout, stderr) ->
    return cb err if err
    cb null, (stdout ? stderr).trim()

printUsage = (args, cb) ->
  console.log  """
    Usage:
    \t #{"gitf <task> [<subtask>|<branch_name>] [options]".bold}

    Tasks:
    \t #{"start".bold}    creates a new branch based on master,
    \t          parameter <branch_name> is required
    \t #{"publish".bold}  publishes the current branch (or given branch) to 
    \t          tracked origin
    \t #{"update".bold}   updates current or given branch with changes from 
    \t          master (via merge)
    \t #{"finish".bold}   merges current or given branch to master, creates 
    \t          new tag and deletes the branch
    \t #{"config".bold}   configuration tools 

    Subtask:
    \t #{"update".bold}   in use with #{"gitf config".bold} will update the gitf program
    \t          to its latest version

    Options:
    \t #{"--tag [<tag>]".bold}
    \t #{"--no-tag".bold} enables, disables, or sets the tag for #{"gitf finish".bold} task,
    \t          the user is prompted to enter tag by default

  """
  return

ensureBranch = (branchName, cb) ->
  git "checkout #{branchName}", (err) ->
    return cb err if err
    console.log "Checked out #{branchName}"
    cb null, branchName

getCurrentBranch = (cb) ->
  git "symbolic-ref HEAD 2>/dev/null | cut -d\"/\" -f 3", cb

tasks = {}

task = (taskName, cb) -> tasks[taskName] = cb

###
  gitf start <branch>
###
task "start", (args, cb) ->
  console.log "Starting new branch...".bold
  newBranch = args._.shift()
  return cb "Enter the name of branch to open" unless newBranch
  syncTasks = []
  syncTasks.push (next) -> 
    ensureBranch config.local.rootBranch, next

  syncTasks.push (next) ->
    git "checkout -b #{newBranch}", (err) ->
      return next err if err
      console.log "Created new branch \"#{newBranch}\""
      next()

  syncTasks.push (next) ->
    console.log "Done.\n"
    console.log """
      Now:
      * you can #{"commit".bold} and #{"publish".bold} your changes with #{"gitf publish".bold} to #{config.remote.repository}, 
      * or update your current branch from #{config.local.rootBranch} with #{"gitf update".bold}. \n
    """
    next()

  async.series syncTasks, cb

###
  gitf publish [<branch>]
###
task "publish", (args, cb) ->
  syncTasks = []
  syncTasks.push (next) ->
    branch = args._.shift()
    next null, branch
  
  syncTasks.push (branch, next) ->
    return getCurrentBranch next unless branch
    next null, branch

  syncTasks.push (branch, next) ->
    return next "Cannot determine git branch - maybe not in a git repository" unless branch
    console.log "Publishing branch \"#{branch}\"...".bold
    # return next "Cannot perform publish on root branch #{branch}" if branch is config.local.rootBranch
    next null, branch

  syncTasks.push ensureBranch

  syncTasks.push (branch, next) ->
    git "push #{config.remote.repository} #{branch}", (err, data) -> next err, branch

  syncTasks.push (branch, next) ->
    console.log "Done. Branch #{branch} published to #{config.remote.repository}/#{branch}."
    next()

  async.waterfall syncTasks, cb

###
  gitf finish [<branch>]
###
task "finish", (args, cb) ->
  syncTasks = []

  syncTasks.push (next) ->
    branch = args._.shift()
    next null, branch
  
  syncTasks.push (branch, next) ->
    return getCurrentBranch next unless branch
    next null, branch

  syncTasks.push (branch, next) ->
    return next "Cannot determine git branch - maybe not in a git repository" unless branch
    console.log "Finishing branch \"#{branch}\"...".bold
    return next "Cannot perform finish on root branch #{branch}" if branch is config.local.rootBranch
    next null, branch

  syncTasks.push (branch, next) ->
    ensureBranch config.local.rootBranch, (err) -> next err, branch

  syncTasks.push (branch, next) ->
    git "merge --no-ff --no-edit #{branch}", (err) ->
      console.log "Branch #{branch} merged to #{config.local.rootBranch}" unless err
      next err, branch

  syncTasks.push (branch, next) ->
    git "tag -l", (err, data) ->
      next err, branch, data.split "\n"

  syncTasks.push (branch, tags, next) ->
    return next null, branch, null if args.tag is false
    tag = args.tag if typeof args.tag is "string"
    return next null, branch, tag if tag

    getTag = () ->
      process.stdout.write "Enter commit tag (press enter to skip): "

    process.stdin.resume()
    process.stdin.on "data", (data) -> 
      tag = data.toString().trim()
      if not tag.length or tag not in tags
        return next null, branch, tag.toString().trim() 
      else
        console.log "Tag #{tag.bold} already exists!".red
        return getTag()
    
    getTag()

  syncTasks.push (branch, tag, next) ->
    return next null, branch unless tag
    git "tag #{tag}", (err) -> 
      console.log "Commit tagged with #{tag}." unless err
      next err, branch

  syncTasks.push (branch, next) ->
    git "branch -d #{branch}", (err) -> 
      console.log "Deleted branch #{branch}." unless err
      next err

  syncTasks.push (next) ->
    console.log "Done."
    next()

  async.waterfall syncTasks, cb

###
  gitf update
###
task "update", (args, cb) ->
  getCurrentBranch (err, branch) ->
    return cb err if err
    return cb "Cannot update root branch with itself" if branch is config.local.rootBranch
    git "merge --no-ff --no-edit #{config.local.rootBranch}", (err) ->
      console.log "Done. Branch #{config.local.rootBranch.bold} merged to #{branch.bold}." unless err
      return cb err

###
  gitf [usage]
###
task "usage", (args, cb) ->
  console.log "\n#{"GITFS".bold} - a simple git dev-flow tool"
  printUsage args, cb

###
  gitf config <config_task>
###
task "config", (args, cb) ->
  subTask = args._.shift()
  if subTask is "update"
    process = exec """curl "#{config.install.url}" | sh """
    process.stdout.on "data", console.log
    process.stderr.on "data", console.log
    process.on "close", (code) ->
      return cb "Update failed" if code > 0
      cb()

callback = (err, data) ->
  if err
    err = err.message.trim() if err.message
    if typeof err is "string"
      process.stderr.write "ERROR: #{err} ".redBG.white.bold
      process.stderr.write "\r\n"
    else
      console.log err
    printUsage()
    process.exit 1
  process.exit 0

runTask = (args, cb) ->
  taskName = args._.shift()
  taskName = "usage" unless taskName
  return cb "Task #{taskName} does not exist!" unless tasks[taskName]
  tasks[taskName] args, cb

runTask argv, callback
