local M = {}

local projects = {}
local baseLspConfigs = {}

M.lspConfigs = baseLspConfigs

local UserConfig = nil

local function getFileNameWithoutExt(path)
  return vim.fs.basename(path):gsub("%.%w+$", "")
end

---@param fileName string
---@param path string
local function loadOneProject(fileName, path)
  local filePath = path .. fileName

  local project = dofile(filePath)

  if project.name == nil then
    project.name = getFileNameWithoutExt(fileName)
  end
  project.lspConfigs = project.lspConfigs or {}
  project.filePath = filePath
  projects[project.path] = project
end

---@param path string
local function loadProjects(path)
	for _, fileName in ipairs(vim.fn.readdir(path,
    function (fileName)
      return vim.filetype.match({ filename = fileName }) == "lua"
    end)
  ) do
    loadOneProject(fileName, path)
  end
end

local function loadOneBaseLspConfig(fileName, path)
  local config = dofile(path .. fileName)
  baseLspConfigs[getFileNameWithoutExt(fileName)] = config
end

local function loadBaseLspConfigs(path)
	for _, fileName in ipairs(vim.fn.readdir(path,
    function (fileName)
      return vim.filetype.match({ filename = fileName }) == "lua"
    end)
  ) do
    loadOneBaseLspConfig(fileName, path)
  end
end

---@param userConfig { projectsPath: string, lspConfigsPath: string }
function M.setup(userConfig)
  UserConfig = userConfig
  loadProjects(userConfig.projectsPath)
  loadBaseLspConfigs(userConfig.lspConfigsPath)
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

-- TODO factoriser un peu cette merde
local function modifyLspConfigBeforeInit(preConfig)
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

return M
