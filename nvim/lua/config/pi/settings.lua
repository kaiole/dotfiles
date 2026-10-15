-- Conversation-local controls; never mutate Pi's model in the middle of a run.
local M = {}
local Settings = {}
Settings.__index = Settings

local function notify(message, level)
	vim.notify("Pi: " .. message, level or vim.log.levels.INFO)
end

function Settings:busy()
	local task = self.owner.task
	return task and (not task.done or task.awaiting_ack)
end

function Settings:refresh()
	if not self.owner.disposed then
		self.owner.view:refresh_attachments()
	end
end

function Settings:sync(state)
	self.model = state.model
	self.thinking = state.thinkingLevel
	self:refresh()
end

function Settings:labels()
	local model = self.model and (self.model.provider .. "/" .. self.model.id) or "default model"
	local thinking = self.thinking or "default thinking"
	if self.pending_model then
		model = model .. " → " .. self.pending_model.provider .. "/" .. self.pending_model.id
		thinking = thinking .. " → model default"
	elseif self.pending_thinking then
		thinking = thinking .. " → " .. self.pending_thinking
	elseif self.operation then
		thinking = thinking .. " …"
	end
	return model, thinking
end

function Settings:label()
	local model, thinking = self:labels()
	return model .. " · " .. thinking
end

function Settings:reset()
	-- Invalidate callbacks from pickers, startup, and requests on an old client.
	self.operation = nil
	self.model, self.thinking = nil, nil
	self.pending_model, self.pending_thinking = nil, nil
	self.deferred_thinking = false
end

function Settings:current(operation)
	return not self.owner.disposed
		and not self.owner.lost
		and self.operation == operation
		and self.owner.client == operation.client
end

function Settings:finish(operation)
	if not self:current(operation) then
		return
	end
	self.operation = nil
	self:refresh()
	self:flush()
end

function Settings:fail(operation, err, mutating)
	if not self:current(operation) then
		return
	end
	self.operation = nil
	self.deferred_thinking = false
	if mutating and (err.code ~= "rpc" or mutating == "readback") then
		-- A timeout abandons correlation, not remote execution. Do not submit
		-- with settings whose application is uncertain, or retry them silently.
		self.owner.lost = true
		operation.client:stop()
		notify("Settings change uncertain: " .. err.message .. " · :PiNew required; draft kept", vim.log.levels.ERROR)
	else
		notify(err.message, vim.log.levels.ERROR)
	end
	self:refresh()
end

function Settings:request(operation, command, callback, mutating)
	operation.client:request(command, function(err, data)
		if not self:current(operation) then
			return
		end
		if err then
			self:fail(operation, err, mutating)
		else
			callback(data)
		end
	end)
end

function Settings:select(operation, items, options, callback)
	local ok, err = pcall(vim.ui.select, items, options, callback)
	if not ok then
		self:fail(operation, { code = "ui", message = "Settings picker failed: " .. tostring(err) })
	end
end

function Settings:begin()
	if self.owner.disposed then
		return
	end
	if self.owner.lost then
		notify("Conversation process was lost. Use :PiNew first.", vim.log.levels.WARN)
		return
	end
	if self.operation then
		notify("Finish the current settings picker/change first", vim.log.levels.WARN)
		return
	end
	if self.owner.client and (self.owner.client.status == "starting" or self.owner.client.status == "stopping") then
		notify("Pi is starting/stopping; try the picker once it is ready", vim.log.levels.WARN)
		return
	end
	self.owner:workspace_for_source()
	local operation = { client = self.owner.client or self.owner:create_client() }
	self.operation = operation
	self:refresh()
	return operation
end

function Settings:ready(operation, callback)
	local client = operation.client
	if client.status == "running" then
		callback()
	else
		client:start(function(err, state)
			if not self:current(operation) then
				return
			end
			if err then
				self:fail(operation, err)
			else
				self:sync(state)
				callback()
			end
		end)
	end
end

function Settings:pick_model()
	local operation = self:begin()
	if not operation then
		return
	end
	self:ready(operation, function()
		self:request(operation, { type = "get_available_models" }, function(data)
			local models = data.models or {}
			if #models == 0 then
				notify("No available models; configure credentials in Pi first", vim.log.levels.WARN)
				self:finish(operation)
				return
			end
			table.sort(models, function(a, b)
				return a.provider .. "/" .. a.id < b.provider .. "/" .. b.id
			end)
			local selected = self.pending_model or self.model
			self:select(operation, models, {
				prompt = "Pi model (next request):",
				format_item = function(model)
					local active = selected and selected.provider == model.provider and selected.id == model.id
					return model.provider .. "/" .. model.id .. (active and " [selected]" or "")
				end,
			}, function(model)
				if not self:current(operation) then
					return
				end
				if model then
					self.pending_model = model
					-- A level picked for the previous model must not silently override
					-- the new model's default/capability-clamped thinking level.
					self.pending_thinking = nil
					if self:busy() then
						notify("Model queued for after the current answer: " .. model.provider .. "/" .. model.id)
					end
				end
				self:finish(operation)
			end)
		end)
	end)
end

function Settings:pick_thinking()
	if self.pending_model and not self.operation and not self.owner.disposed and not self.owner.lost then
		-- RPC discovers levels for the active model only. Wait for the queued
		-- model to become active rather than offer the wrong model's levels.
		self.deferred_thinking = true
		notify("Thinking picker will open once the queued model is active")
		self:flush()
		return
	end
	local operation = self:begin()
	if not operation then
		return
	end
	self:ready(operation, function()
		self:request(operation, { type = "get_available_thinking_levels" }, function(data)
			local levels = data.levels or {}
			if #levels == 0 then
				notify("Pi returned no supported thinking levels", vim.log.levels.WARN)
				self:finish(operation)
				return
			end
			local selected = self.pending_thinking or self.thinking
			self:select(operation, levels, {
				prompt = "Pi thinking (next request):",
				format_item = function(level)
					return level .. (level == selected and " [selected]" or "")
				end,
			}, function(level)
				if not self:current(operation) then
					return
				end
				if level then
					self.pending_thinking = level
					if self:busy() then
						notify("Thinking level queued for after the current answer")
					end
				end
				self:finish(operation)
			end)
		end)
	end)
end

function Settings:flush()
	if self.owner.disposed or self.owner.lost or self.operation or self:busy() then
		return
	end
	local model, thinking = self.pending_model, self.pending_thinking
	if not model and not thinking then
		if self.deferred_thinking then
			self.deferred_thinking = false
			self:pick_thinking()
		end
		return
	end
	local operation = self:begin()
	if not operation then
		return
	end
	self.pending_model, self.pending_thinking = nil, nil
	self:refresh()
	local before = self.thinking
	local command = model and { type = "set_model", provider = model.provider, modelId = model.id }
		or { type = "set_thinking_level", level = thinking }
	self:request(operation, command, function()
		-- set_model can change thinking; set_thinking_level has no response data.
		-- Always read back effective state instead of displaying our requested value.
		self:request(operation, { type = "get_state" }, function(state)
			self:sync(state)
			local adjustment = model and before and before ~= self.thinking
			notify(
				"Using "
					.. (self.model and (self.model.provider .. "/" .. self.model.id) or "no model")
					.. " · "
					.. (self.thinking or "off")
					.. (adjustment and " (thinking adjusted from " .. before .. ")" or "")
			)
			self:finish(operation)
		end, "readback")
	end, true)
end

function M.new(owner)
	return setmetatable({ owner = owner }, Settings)
end

return M
