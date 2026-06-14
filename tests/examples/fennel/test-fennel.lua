local people = {{name = "Alice", age = 30, role = "developer"}, {name = "Bob", age = 17, role = "student"}, {name = "Charlie", age = 25, role = "developer"}, {name = "Diana", age = 35, role = "manager"}, {name = "Eve", age = 16, role = "student"}}
local adults
do
  local tbl_26_ = {}
  local i_27_ = 0
  for _, p in ipairs(people) do
    local val_28_
    if (p.age >= 18) then
      val_28_ = p.name
    else
      val_28_ = nil
    end
    if (nil ~= val_28_) then
      i_27_ = (i_27_ + 1)
      tbl_26_[i_27_] = val_28_
    else
    end
  end
  adults = tbl_26_
end
local developers
do
  local tbl_26_ = {}
  local i_27_ = 0
  for _, p in ipairs(people) do
    local val_28_
    do
      local case_3_ = p.role
      if (case_3_ == "developer") then
        val_28_ = p.name
      else
        val_28_ = nil
      end
    end
    if (nil ~= val_28_) then
      i_27_ = (i_27_ + 1)
      tbl_26_[i_27_] = val_28_
    else
    end
  end
  developers = tbl_26_
end
print(("Adults:     " .. table.concat(adults, ", ")))
return print(("Developers: " .. table.concat(developers, ", ")))