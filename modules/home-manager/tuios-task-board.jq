def row(t; multi): "  \(if t.blocked then "!" else " " end)\(if multi then "\(t.session)/" else "" end)\(t.id) \(t.title[0:20])";
def group(name; color; items; multi):
  if (items | length) > 0 then
    ["\u001b[1;38;2;\(color)m\(name) \(items | length)\u001b[0m"]
    + (items | map("\u001b[38;2;\(color)m\(row(.; multi))\u001b[0m"))
  else [] end;
(.tasks // []) as $tasks
| ($tasks | map(select(.stage != "done" and .stage != "shipped"))) as $open
| ($open | map(select(.holder == null and .blocked == null and (.stage | IN("doing", "verify", "review"))))) as $abandoned
| ($open | map(.session) | unique | length > 1) as $multi
| (
    group("↺ abandoned"; "255;56;139"; $abandoned; $multi)
    + group("doing"; "0;164;255"; ($open | map(select(.stage == "doing" and (.holder != null or .blocked != null)))); $multi)
    + group("verify"; "255;152;90"; ($open | map(select(.stage == "verify" and (.holder != null or .blocked != null)))); $multi)
    + group("review"; "255;152;90"; ($open | map(select(.stage == "review" and (.holder != null or .blocked != null)))); $multi)
    + group("todo"; "133;131;146"; ($open | map(select(.stage == "todo"))); $multi)
    + group("plan"; "133;131;146"; ($open | map(select(.stage == "plan"))); $multi)
  )
| if length == 0 then ["\u001b[38;2;133;131;146mno open cards\u001b[0m"] else . end
| join("\n")
