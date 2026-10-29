import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

// Explicit opt-in: briefly focuses Finder, moves the pointer, captures (never saves), then restores focus.
assert.equal(process.argv[2], "--run", "Use --run for the bounded live check");
const directory = `${process.env.HOME}/.hammerspoon`;
const read = name => JSON.parse(readFileSync(`${directory}/${name}`, "utf8"));
const hash = () => createHash("sha256").update(readFileSync(`${directory}/xspoon_registry.json`)).digest("hex");
function lua(code) {
  const escaped = code.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
  return JSON.parse(execFileSync("/usr/bin/osascript", ["-e", `tell application "Hammerspoon" to execute lua code "${escaped}"`],
    { encoding: "utf8", timeout: 15000 }).trim());
}
const beforeHash = hash();
let oldID;
try { oldID = read("local_element_latest.json").captureID; } catch {}
let result;
let finderWindow;
try {
  lua(`__XSpoonInputProbe={app=hs.application.frontmostApplication(),point=hs.mouse.absolutePosition(),clipboard=hs.pasteboard.readAllData()}; return hs.json.encode({ok=true})`);
  finderWindow = Number(execFileSync("/usr/bin/osascript", ["-e", 'tell application "Finder"\nset w to make new Finder window to POSIX file "/tmp"\nactivate\nreturn id of w\nend tell'], { encoding: "utf8", timeout: 10000 }).trim());
  await delay(1000);
  const target = lua(`local app=hs.application.get("com.apple.finder"); local w=app:focusedWindow(); local f=w:frame(); local p={x=f.x+260,y=f.y+36}; local b=hs.axuielement.systemElementAtPosition(p); hs.mouse.absolutePosition(p); return hs.json.encode({app=app:bundleID(),role=b:attributeValue("AXRole"),description=b:attributeValue("AXDescription"),point=p,window=w:title()})`);
  assert.equal(target.role, "AXButton", "The probe must point at a real button before testing keys");
  const chord = key => lua(`hs.timer.doAfter(0.05,function() hs.eventtap.keyStroke({"ctrl","alt"},"${key}",1000) end); return hs.json.encode({sent=true})`);
  chord("i");
  await delay(650);
  assert.equal(read("xspoon_inspection_state.json").active, true);
  assert.equal(read("live_element_latest.json").bundleID, "com.apple.finder");
  assert.equal(read("live_element_latest.json").role, "AXButton");
  lua(`hs.timer.doAfter(0.05,function() hs.eventtap.keyStroke({},"escape",1000) end); return hs.json.encode({sent=true})`);
  await delay(400);
  assert.equal(read("xspoon_inspection_state.json").active, false);
  assert.equal(read("local_element_latest.json").captureID, oldID, "Escape must not capture");
  chord("i");
  await delay(400);
  assert.equal(read("xspoon_inspection_state.json").active, true);
  lua(`hs.timer.doAfter(0.05,function() hs.eventtap.keyStroke({},"return",1000) end); return hs.json.encode({sent=true})`);
  await delay(1200);
  const capture = read("local_element_latest.json");
  assert.notEqual(capture.captureID, oldID);
  assert.equal(capture.bundleID, "com.apple.finder");
  assert.equal(capture.role, "AXButton");
  assert.equal(read("xspoon_inspection_state.json").active, false);
  const sheet = lua(`local app=hs.application.get("com.singleton23.XSpoon"); local root=hs.axuielement.applicationElement(app); local sheets,saves=0,0; local visited=0; local function walk(e,depth) if depth>10 or visited>700 then return end; visited=visited+1; local role=e:attributeValue("AXRole"); local label=e:attributeValue("AXTitle") or e:attributeValue("AXDescription"); if role=="AXSheet" then sheets=sheets+1 end; if role=="AXButton" and label=="Save Shortcut" then saves=saves+1 end; for _,c in ipairs(e:attributeValue("AXChildren") or {}) do walk(c,depth+1) end end; walk(root,0); return hs.json.encode({sheets=sheets,saveButtons=saves,visited=visited})`);
  assert.equal(sheet.sheets, 1, "Exactly one shortcut setup sheet must open");
  assert.equal(sheet.saveButtons, 1);
  assert.equal(hash(), beforeHash, "Capture must not change any saved action");
  result = { status: "pass", target, captureID: capture.captureID, sheet, registryUnchanged: true,
    evidence: "Translated Ctrl+Alt+I event, Escape cancel, then Enter capture through real Hammerspoon event tap and XSpoon sheet" };
} finally {
  lua(`__SCRIPTS__.stopLiveInspector(); local app=hs.application.get("com.singleton23.XSpoon"); if app then local n=0; local function cancel(e,d) if d>10 or n>700 then return false end; n=n+1; local label=e:attributeValue("AXTitle") or e:attributeValue("AXDescription"); if e:attributeValue("AXRole")=="AXButton" and label=="Cancel" then e:performAction("AXPress"); return true end; for _,c in ipairs(e:attributeValue("AXChildren") or {}) do if cancel(c,d+1) then return true end end; return false end; cancel(hs.axuielement.applicationElement(app),0) end; if __XSpoonInputProbe then hs.mouse.absolutePosition(__XSpoonInputProbe.point); hs.pasteboard.writeAllData(__XSpoonInputProbe.clipboard); if __XSpoonInputProbe.app then __XSpoonInputProbe.app:activate(true) end end; __XSpoonInputProbe=nil; return hs.json.encode({restored=true})`);
  if (Number.isInteger(finderWindow)) execFileSync("/usr/bin/osascript", ["-e", `tell application "Finder" to close window id ${finderWindow}`], { timeout: 10000 });
}
console.log(JSON.stringify(result, null, 2));
