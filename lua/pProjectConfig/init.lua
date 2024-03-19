-- TODO better error handling (especially for paths, It's very sketchy rn)
-- TODO hotreload base lsp configs
-- TODO add another pattern to detect a project by name of git distant repos instead of path
-- TODO add keymaps
-- TODO public function to live deload / reload projects
local M = {}

local projects = {}
local baseLspConfigs = {}
local defaultLspConfigs = {}

M.lspConfigs = baseLspConfigs

local UserConfig = nil

local function getFileNameWithoutExt(path)
  return vim.fs.basename(path):gsub("%.%w+$", "")
end

local function getOneProjectFromFilePath(filePath)
  local project = dofile(filePath)
  if type(project) ~= "table" then return nil end
  if project.path == nil then return nil end

  if project.name == nil then
    project.name = getFileNameWithoutExt(filePath)
  end
  project.lspConfigs = project.lspConfigs or {}
  project.filePath = filePath
  return project
end

---@param filePath string
local function loadOneProjectFromFilePath(filePath)
  local project = getOneProjectFromFilePath(filePath)
  if project == nil then return end
  projects[project.path] = project
end

---@param path string
local function loadProjectsFromPath(path)
	for _, fileName in ipairs(vim.fn.readdir(path,
    function (fileName)
      return vim.filetype.match({ filename = fileName }) == "lua"
    end)
  ) do
    loadOneProjectFromFilePath(path .. fileName)
  end
end

local function loadOneBaseLspConfigFromFilePath(filePath)
  local config = dofile(filePath)
  baseLspConfigs[getFileNameWithoutExt(filePath)] = config
end

local function loadBaseLspConfigsFromPath(path)
	for _, fileName in ipairs(vim.fn.readdir(path,
    function (fileName)
      return vim.filetype.match({ filename = fileName }) == "lua"
    end)
  ) do
    loadOneBaseLspConfigFromFilePath(path .. fileName)
  end
end

local function getLspConfigForProjectByServerName(serverName, project)
  if project == nil or project.lspConfigs == nil or project.lspConfigs[serverName] == nil then
    return baseLspConfigs[serverName]
  end
  if baseLspConfigs[serverName] == nil then
    return project.lspConfigs[serverName]
  end
  return vim.tbl_deep_extend("force", baseLspConfigs[serverName], project.lspConfigs[serverName])
end

local function modifyLspConfigBeforeInit(preConfig)
  if defaultLspConfigs[preConfig.name] == nil then
    defaultLspConfigs[preConfig.name] = vim.deepcopy(preConfig)
  end
  local project = projects[preConfig.root_dir]

  local config = getLspConfigForProjectByServerName(preConfig.name, project)
  if config == nil then return end
  for key, value in pairs(config) do
    if type(preConfig[key]) == "table" and type(value) == "table" then
      preConfig[key] = vim.tbl_deep_extend("force", preConfig[key], value)
    else
      preConfig[key] = value
    end
  end
end

function M.beforeInit(func)
  return function (initializeParams, config)
    modifyLspConfigBeforeInit(config)
    if func ~= nil then
      func(initializeParams, config)
    end
  end
end

local function getAutoCmdAugroupName(project)
  return "pProjectConfig(" .. project.path .. ")"
end

local function clearProject(project)
  if project.clearHook ~= nil then
    project.clearHook()
  end
  if project.autoCmdsHook ~= nil then
    -- clear autocmds
    vim.api.nvim_del_augroup_by_name(getAutoCmdAugroupName(project))
  end
end

local currentProject = nil

local function setProject(project)
  currentProject = project
  if project.hook ~= nil then
    project.hook()
  end
  if project.autoCmdsHook ~= nil then
	  local augroup = vim.api.nvim_create_augroup(getAutoCmdAugroupName(project), { clear = true })
    project.autoCmdsHook(augroup)
  end
end

---@param arg { pwd: string }
local function dirChanged(arg)
  local newProject = projects[arg.pwd]
  if newProject == currentProject then
    return
  end
  if currentProject ~= nil then
    clearProject(currentProject)
  end
  if newProject == nil then return end
  setProject(newProject)
end

local function updateLspConfigOfRunningServerForOneProject(project)
  local clients = vim.tbl_filter(function (client)
      return client.config.root_dir == project.path
    end,
    vim.lsp.get_clients())
  for _, client in ipairs(clients) do
    local newConfig = getLspConfigForProjectByServerName(client.config.name, project)
    newConfig = vim.tbl_deep_extend("force", defaultLspConfigs[client.config.name], newConfig)
    -- TODO rn hotreloading only for settings
    if vim.deep_equal(newConfig.settings, client.config.settings) == false then
      client.config = newConfig
	    client.notify("workspace/didChangeConfiguration", { settings = newConfig.settings })
    end
  end
end

local function projectSaved(filePath)
  local project = getOneProjectFromFilePath(filePath)
  if project == nil then return end
  if projects[project.path] == currentProject then
    clearProject(currentProject)
  end
  projects[project.path] = project
  updateLspConfigOfRunningServerForOneProject(project)
  if vim.loop.cwd() == project.path then
    setProject(project)
  end
end

---@param userConfig { projectsPath: string, lspConfigsPath: string, instantTrigger?: boolean }
function M.setup(userConfig)
  UserConfig = userConfig
  loadProjectsFromPath(userConfig.projectsPath)
  loadBaseLspConfigsFromPath(userConfig.lspConfigsPath)
  local augroup = vim.api.nvim_create_augroup("pProjectConfig", { clear = true })

  vim.api.nvim_create_autocmd("DirChanged", {
    pattern = { "*" },
    group = augroup,
    desc = "trigger handlers of pProjectConfig",
    callback = function (ev) dirChanged({ pwd = ev.file }) end
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = { userConfig.projectsPath .. '*.lua' },
    group = augroup,
    desc = "hotreloading of individual project of pProjectConfig",
    callback = function (ev) projectSaved(ev.file) end
  })

  if userConfig.instantTrigger == true then
    dirChanged({ pwd = vim.loop.cwd() })
  end
end

-- TODO auto skeletton with project name + path
local function createProject()
  if UserConfig == nil then return end
	local cwd = vim.loop.cwd()
	vim.ui.input({
		prompt = 'projectName: ',
		default = cwd:sub(cwd:find("[^/]*$"))
	}, function(input)
		if not input then
			return
		end
		local projectFile = UserConfig.projectsPath .. input .. '.lua'
		vim.cmd('e ' .. projectFile)
	end)
end

function M.openOrCreateProject()
	local cwd = vim.loop.cwd()
	local project = projects[cwd]
	if project == nil then
		createProject()
		return
	end
	vim.cmd('e ' .. project.filePath)
end
return M
