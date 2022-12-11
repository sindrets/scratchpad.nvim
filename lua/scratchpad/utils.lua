local M = {}

function M.clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

---Match a given string against multiple patterns.
---@param str string
---@param patterns string[]
---@return ... captured: The first match, or `nil` if no patterns matched.
function M.str_match(str, patterns)
  for _, pattern in ipairs(patterns) do
    local m = { str:match(pattern) }
    if #m > 0 then
      return unpack(m)
    end
  end
end

---Perform a map and also filter out index values that would become `nil`.
---@param t table
---@param func fun(value: any): any?
---@return table
function M.tbl_fmap(t, func)
  local ret = {}

  for key, item in pairs(t) do
    local v = func(item)
    if v ~= nil then
      if type(key) == "number" then
        table.insert(ret, v)
      else
        ret[key] = v
      end
    end
  end

  return ret
end

---@class vector<T> : { [integer]: T }

---Create a shallow copy of a portion of a vector. Negative numbers indexes
---from the end.
---@param t vector
---@param first? integer First index, inclusive. (default: 1)
---@param last? integer Last index, inclusive. (default: `#t`)
---@return vector
function M.vec_slice(t, first, last)
  local slice = {}

  if first and first < 0 then
    first = #t + first + 1
  end

  if last and last < 0 then
    last = #t + last + 1
  end

  for i = first or 1, last or #t do
    table.insert(slice, t[i])
  end

  return slice
end

---Return all elements in `t` between `first` and `last`. Negative numbers
---indexes from the end.
---@param t vector
---@param first integer First index, inclusive
---@param last? integer Last index, inclusive
---@return any ...
function M.vec_select(t, first, last)
  return unpack(M.vec_slice(t, first, last))
end

---Join multiple vectors into one.
---@param ... any
---@return vector
function M.vec_join(...)
  local result = {}
  local args = { ... }
  local n = 0

  for i = 1, select("#", ...) do
    if type(args[i]) ~= "nil" then
      if type(args[i]) ~= "table" then
        result[n + 1] = args[i]
        n = n + 1
      else
        for j, v in ipairs(args[i]) do
          result[n + j] = v
        end
        n = n + #args[i]
      end
    end
  end

  return result
end

---Get the result of the union of the given vectors.
---@param ... vector
---@return vector
function M.vec_union(...)
  local result = {}
  local args = {...}
  local seen = {}

  for i = 1, select("#", ...) do
    if type(args[i]) ~= "nil" then
      if type(args[i]) ~= "table" and not seen[args[i]] then
        seen[args[i]] = true
        result[#result+1] = args[i]
      else
        for _, v in ipairs(args[i]) do
          if not seen[v] then
            seen[v] = true
            result[#result+1] = v
          end
        end
      end
    end
  end

  return result
end

---Get the result of the difference of the given vectors.
---@param ... vector
---@return vector
function M.vec_diff(...)
  local args = {...}
  local seen = {}

  for i = 1, select("#", ...) do
    if type(args[i]) ~= "nil" then
      if type(args[i]) ~= "table" then
        if i == 1  then
          seen[args[i]] = true
        elseif seen[args[i]] then
          seen[args[i]] = nil
        end
      else
        for _, v in ipairs(args[i]) do
          if i == 1 then
            seen[v] = true
          elseif seen[v] then
            seen[v] = nil
          end
        end
      end
    end
  end

  return vim.tbl_keys(seen)
end

---Get the result of the symmetric difference of the given vectors.
---@param ... vector
---@return vector
function M.vec_symdiff(...)
  local result = {}
  local args = {...}
  local seen = {}

  for i = 1, select("#", ...) do
    if type(args[i]) ~= "nil" then
      if type(args[i]) ~= "table" then
        seen[args[i]] = seen[args[i]] == 1 and 0 or 1
      else
        for _, v in ipairs(args[i]) do
          seen[v] = seen[v] == 1 and 0 or 1
        end
      end
    end
  end

  for v, state in pairs(seen) do
    if state == 1 then
      result[#result+1] = v
    end
  end

  return result
end

---Return the first index a given object can be found in a vector, or -1 if
---it's not present.
---@param t vector
---@param v any
---@return integer
function M.vec_indexof(t, v)
  for i, vt in ipairs(t) do
    if vt == v then
      return i
    end
  end
  return -1
end

---Append any number of objects to the end of a vector. Pushing `nil`
---effectively does nothing.
---@param t vector
---@param ... any
---@return vector t
function M.vec_push(t, ...)
  local args = {...}

  for i = 1, select("#", ...) do
    t[#t + 1] = args[i]
  end

  return t
end

---Remove an object from a vector.
---@param t vector
---@param v any
---@return boolean success True if the object was removed.
function M.vec_remove(t, v)
  local idx = M.vec_indexof(t, v)

  if idx > -1 then
    table.remove(t, idx)

    return true
  end

  return false
end

return M
