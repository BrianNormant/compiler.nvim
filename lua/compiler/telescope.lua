--- ### Frontend for compiler.nvim

local M = {}

function M.show()
  -- If working directory is home, don't open telescope.
  if vim.loop.os_homedir() == vim.loop.cwd() then
    vim.notify("You must :cd your project dir first.\nHome is not allowed as working dir.", vim.log.levels.WARN, {
      title = "Compiler.nvim"
    })
    return
  end

  -- Dependencies
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local state = require "telescope.actions.state"
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local utils = require("compiler.utils")
  local utils_bau = require("compiler.utils-bau")

  local buffer = vim.api.nvim_get_current_buf()

  -- If a flake.nix is present in cwd, list flake packages and build/run them

  local nix_options = {}
  if vim.fn.filereadable(vim.loop.cwd() .. '/flake.nix') then
    local obj = vim.system({'nix','flake','show','--json'}, {text=true}):wait()
    if obj.code == 1 then
      vim.notify("Current flake.nix is malformed and can't be evaluated")
      return
    end
    local flake = vim.fn.json_decode(obj.stdout)

    if flake.packages ~= nil then
      for system, packages in pairs(flake.packages) do
        if system ~= "x86_64-linux" then goto continue end
        for name,p in pairs(packages) do
          if name == "default" then
            table.insert(
              nix_options,
              { text = "Nix Run", value = ".", nix = true }
            )
          else
            table.insert(
              nix_options,
              { text = "Nix Run " .. name, value = ".#" .. name, nix = true }
            )
          end
        end
         ::continue::
      end
    end
  end

  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buffer })




  -- POPULATE
  -- ========================================================================

  local options = nix_options

  if not next(options) then
    local language = utils.require_language(filetype)
    -- On unsupported languages, default to make.
    if not language then language = utils.require_language("make") or {} end

    -- Also show options discovered on Makefile, Cmake... and other bau.
    if not language.bau_added then
      language.bau_added = true
      local bau_opts = utils_bau.get_bau_opts()

      for _, item in ipairs(language.options) do
        table.insert(options, item)
      end
      -- Insert a separator on telescope for every bau.
      local last_bau_value = nil
      for _, item in ipairs(bau_opts) do
        if last_bau_value ~= item.bau then
          table.insert(options, { text = "", value = "separator" })
          last_bau_value = item.bau
        end
        table.insert(options, item)
      end
    end
  end



  -- Add numbers in front of the options to display.
  local index_counter = 0
  for _, option in ipairs(options) do
    if option.value ~= "separator" then
      index_counter = index_counter + 1
      option.text = index_counter .. " - " .. option.text
    end
  end

  -- RUN ACTION ON SELECTED
  -- ========================================================================

  --- On option selected → Run action depending of the language.
  local function on_option_selected(prompt_bufnr)
    actions.close(prompt_bufnr) -- Close Telescope on selection
    local selection = state.get_selected_entry()
    if selection.value == "" then return end -- Ignore separators

    if selection then
      -- Do the selected option belong to a build automation utility?
      local bau = nil
      local nix = nil
      for _, value in ipairs(options) do
        if value.nix then
          nix = true
        elseif value.text == selection.display then
          bau = value.bau
        end
      end

      if nix then
        local option = selection.value
        local overseer = require("overseer")
        local final_message = "--task finished"
        local task = overseer.new_task {
          name = "- Make interpreter",
          strategy = { "orchestrator",
          tasks = {{ name = "- Nix run → nix run " .. option ,
          cmd = "nix run "    .. option ..                                   -- run
          " && echo nix run " .. option ..                                  -- echo
          " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},}
        task:start()
        -- then
        -- clean redo (language)
        _G.compiler_redo_selection = nil
        -- save redo (nix)
        _G.compiler_redo_nix_selection = selection.value
        _G.compiler_redo_nix = true
      elseif bau then -- call the bau backend.
        bau = utils_bau.require_bau(bau)
        if bau then bau.action(selection.value) end
        -- then
        -- clean redo (language)
        _G.compiler_redo_selection = nil
        -- save redo (bau)
        _G.compiler_redo_bau_selection = selection.value
        _G.compiler_redo_bau = bau
      else -- call the language backend.
        language.action(selection.value)
        -- then
        -- save redo (language)
        _G.compiler_redo_selection = selection.value
        _G.compiler_redo_filetype = filetype
        -- clean redo (bau)
        _G.compiler_redo_bau_selection = nil
        _G.compiler_redo_bau = nil
      end

    end
  end


  -- SHOW TELESCOPE
  -- ========================================================================
  local function open_telescope()
    pickers
      .new({}, {
        prompt_title = "Compiler",
        results_title = "Options",
        finder = finders.new_table {
          results = options,
          entry_maker = function(entry)
            return {
              display = entry.text,
              value = entry.value,
              ordinal = entry.text,
            }
          end,
        },
        sorter = conf.generic_sorter(),
        attach_mappings = function(_, map)
          map(
            "i",
            "<CR>",
            function(prompt_bufnr) on_option_selected(prompt_bufnr) end
          )
          map(
            "n",
            "<CR>",
            function(prompt_bufnr) on_option_selected(prompt_bufnr) end
          )
          return true
        end,
      })
      :find()
  end
  open_telescope() -- Entry point
end

return M
