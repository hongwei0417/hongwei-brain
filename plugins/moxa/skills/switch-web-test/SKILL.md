---
name: switch-web-test
description: Browser-based functional testing for Moxa switch web interfaces (MDS / RKS series on MX-NOS). This skill should be used when verifying switch web application functionality end-to-end through browser automation, running the full feature checklist from Notion with both GET and mutation validation, testing Angular-based Moxa switch dev servers on localhost, or generating comprehensive test reports per device model. Trigger on "test switch web", "verify web functionality", "browser test", "smoke test switch", "functional test", "web test report", "test MDS-L2/L3/RKS", "verify switch web MR", or any request to run through the MDS/RKS Notion checklist.
---

# Switch Web Test

Runs the full MDS/RKS Notion feature checklist against a Moxa switch web dev server. Logs in, iterates every testable feature, verifies **both GET and a safe mutation** per page, and writes a structured report. Designed to run fully autonomously — no per-page confirmation.

## Prerequisites

- Target switch dev server running on a local port (default: `http://localhost:4200`)
- Chrome with the Claude-in-Chrome extension connected
- Notion tab open to the MDS/RKS checklist (or API access)

## Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--url` | No | `http://localhost:4200` | Dev server URL |
| `--app` | No | auto-detect (from login page title) | Target model (e.g., `mds-l3`, `mds-l2`, `mds-l2-4xg`, `rks-l2`) |
| `--user` | No | `admin` | Login username |
| `--pass` | No | `moxa` | Login password |

Example: `/switch-web-test --app=mds-l3`

## Default credentials

Unless the user says otherwise, assume `admin` / `moxa`. Do NOT pause to ask for credentials — the user has already pre-authorized this pair for the dev-server environment. If login fails with those, then stop and ask.

## Autonomous flow (no per-page confirmation)

Run the entire checklist end-to-end without pausing between features. The user gave explicit standing instructions: don't ask "這一頁要自動測試嗎？" per feature. Only stop to ask the user when:
- Login credentials fail
- An unexpected error pattern repeats across several pages and you can't recover
- The dev server is unreachable or the app name doesn't match the user's intent
- You encounter a destructive action the user hasn't explicitly green-lit

Low-risk and "probably-fine" pages still get exercised — don't skip a page just because it looks trivial.

## Notion checklist source

**Primary URL**: `https://www.notion.so/lynn-second-brain/MDS-RKS-91dbc641c3fc4fde8f06502a5643a483`

### Reliable parsing

The Notion API (`mcp__claude_ai_Notion__fetch`) often returns 404 on this page depending on integration scopes. **Fall back to reading the already-open browser tab** — the user typically has it open. Use `mcp__claude-in-chrome__javascript_tool` on the Notion tab:

```js
(() => {
  const cells = Array.from(document.querySelectorAll('[placeholder=" "]')).map(c => c.textContent.trim());
  // First 3 items = legend (✅/❌/⚠️), next 6 = header row (分類, 功能頁面, MDS-L2, MDS-L2-4XG, MDS-L3, RKS-L2)
  const rows = [];
  for (let i = 9; i + 5 < cells.length; i += 6) {
    rows.push({
      category: cells[i],
      feature: cells[i + 1],
      'MDS-L2': cells[i + 2],
      'MDS-L2-4XG': cells[i + 3],
      'MDS-L3': cells[i + 4],
      'RKS-L2': cells[i + 5],
    });
  }
  return rows;
})()
```

Pick the column that matches the target model from `--app`. Rows where the target column contains ✅ / ❌ / ⚠️ / written description are already-noted — still include in the report but mark why. Rows with `x` = N/A for that model. Empty = untested (these are the primary focus).

## Workflow

### Phase 1: Setup & login

1. `mcp__claude-in-chrome__tabs_context_mcp` to list tabs.
2. Navigate the dev-server tab to `<url>/dashboard`. If the tab title doesn't match `--app`, either the URL is pointing at a different backend or the server needs a refresh. If the title differs, ask the user before proceeding.
3. If redirected to `/login`: fill username + password, press Return.
4. Wait ~3s, then close the "Login Records" welcome dialog (`button` with text `"Close"`). Use a JS helper that's idempotent:
   ```js
   document.querySelectorAll('button').forEach(b => { if ((b.textContent||'').trim() === 'Close') b.click(); });
   ```
5. Confirm `location.pathname === '/dashboard'` before moving on.

### Phase 2: Parse checklist + build plan

1. Read rows from the Notion tab (see parsing above).
2. For each row, decide:
   - **Auto-test**: target-column is empty or already has a marker we want to re-verify. This is the default bucket.
   - **N/A**: target-column is `x` — still record in the report under "N/A per Notion".
3. Build an internal list of features to exercise in order. Don't prompt the user for this list.

### Phase 3: Run every page

For each feature:

1. **Navigate** — preferred order:
   - Click the sidebar item via coordinate or `find` ref (sidebar clicks preserve session).
   - Fallback to direct URL navigation if sidebar click is a no-op.
2. **Wait 2-3s** then `mcp__claude-in-chrome__read_network_requests` with `urlPattern: "/api/"` and `clear: true` to snapshot what the page load fetched. GET 2xx on every request = GET pass.
3. **Attempt a safe mutation** (see next section for the decision tree). Confirm via `urlPattern: "save"` that a PATCH/POST returned 2xx. Then **revert**.
4. Record the result row in memory (feature, category, GET status, mutation status, PATCH endpoints, notes).

Don't take a screenshot for every page. Only screenshot when a page fails or looks unexpected.

### Phase 4: Write the report

Write to `TEST-REPORT-<APP>-<YYYY-MM-DD>.md` in repo root. See the template section at the bottom.

## Mutation policy — this is the whole point of the skill

**Every feature in the checklist must be verified with both a GET and a mutation.** A GET-only result is not acceptable coverage — if a page's PATCH isn't exercised, that page is effectively untested no matter how nicely its read path renders. The user has explicitly asked to stop hedging here: GET-only is a last resort, not a comfortable default.

### Only two categories may skip the mutation

The user's rule: **the only pages allowed to be GET-only are ones related to the management interface itself or the firmware / persistent config.** Everything else — user accounts, online sessions, system time, VLAN, trusted access, redundancy protocols, routing, security, QoS, per-port tables, SNMP, email, DNS, NTP, etc. — must be mutated and reverted. If a page looks scary, that's a signal to look harder for a safe workaround, not a license to skip.

- **Interface-related** (touching mgmt access paths) = may skip: Network Interface, User Interface (HTTP/HTTPS/SSH service toggles), SSH & SSL (certs).
- **Firmware / persistent-config-related** (touching the boot image or whole-config blob) = may skip: Firmware Upgrade, Config Backup and Restore.

Anything outside those two buckets is **not** a valid skip reason. "Feels risky" isn't interface or firmware. "Might re-converge the topology briefly" isn't interface or firmware. Find a workaround.

### Default stance: be bold, then be bolder

A short value toggle that's reverted in the same session is almost always safe, even on pages named "Static Routing", "MACsec", or "Spanning Tree". The genuinely dangerous mutations are the narrow set above — ones that actually drop the TCP/TLS session to the box or rewrite the boot image. Everything else recovers in seconds.

If you catch yourself writing "GET-only, skipped for safety" in the report for a page that isn't interface- or firmware-related, stop and re-read the workarounds below before giving up.

### Safe test targets — key trick for per-port pages

Most "risky-sounding" pages (PoE, Port Settings, Port Security, Link Aggregation, ACL, 802.1X, MAC Auth Bypass, MACsec, Binding DB, IP Source Guard, Port and VLAN Mirroring, Ingress Rate Limit, Egress Shaper, Scheduler, GARP, Traffic Storm Control, Dynamic ARP Inspection, DHCP Snooping port settings, Static Unicast/Multicast…) are **per-port** tables. Always pick a port that is:

1. **Marked "Not installed"** (ports 2/1–2/4 on MDS-G4020 4-module chassis). Best target — the port physically isn't there.
2. If all ports are installed, pick one that is **admin-down / Disabled / unconnected** (Link Status = "--" or "Link down"). These aren't carrying mgmt traffic so poking them is safe.
3. **Never** pick the port on which mgmt traffic flows. For MDS-L3 that's usually 1/1 (10.123.8.53 reachable via it). If unsure, avoid 1/1.

With this rule, almost all Port / Security / QoS per-port pages become testable.

### Safe mutation patterns

The Moxa save API always looks like `/api/v1/setting/data/<resource>?save` (PATCH). A successful save flow is: toggle value → click Apply → observe PATCH 200 → revert via a second toggle+Apply. Always revert in the same session so device state ends unchanged.

| Pattern | Example pages | How |
|---------|---------------|-----|
| Global Enable/Disable dropdown toggle | IGMP Snooping, GMRP, DHCP Snooping, DHCP Relay, Loop Protection, MMS, GOOSE Check, Modbus TCP, EtherNet/IP, Tracking, OSPF, RIP, NTP Server, Modbus TCP, 802.1X global, Hardware Interfaces (USB) | Click dropdown → Enabled → Apply → verify PATCH 200 → revert to Disabled → Apply |
| Text field edit with revert | Information Settings (Location), SNMP (Read Community `public`→`publictest`→`public`), PROFINET (System Name), DNS Settings (Primary DNS), Email Settings (TCP Port 25→26) | Triple-click field → type test value → Apply → PATCH 200 → triple-click → restore original → Apply |
| Numeric/dropdown edit on **Not-installed or admin-down port** | PoE (port toggle), Port Settings (port description / speed), Link Aggregation (per-port), GARP, Traffic Storm Control, Ingress Rate Limit, Egress Shaper, Scheduler, Port Security, 802.1X per-port, MAC Auth Bypass, MACsec, Binding DB, IP Source Guard, Dynamic ARP Inspection, ACL per-port, Port and VLAN Mirroring, Static Multicast per-port | Pick a port marked "Not installed" or admin-down → edit one field → Apply → PATCH 200 → re-open → restore → Apply. **Check client-side range validators first** (e.g. Ingress CIR is 1-1000 Mbps) |
| Per-row edit dialog with revert | Password Policy, Event Notifications (single event Enabled toggle), Classification (DSCP 0 CoS 0→1), Login Policy (auto-logout timeout within reason), Syslog (server entry), SNMP Trap (destination entry), Login Authentication (order), RADIUS / TACACS+ (add dummy server 127.0.0.2 and delete), Static Routing (add dummy route for `10.99.99.0/24` and delete — **never touch default route**) | Click edit pencil → toggle one field → Apply → PATCH 200 → reopen → revert |
| Confirmation dialog ("non-secure protocol") | MMS, Modbus TCP, EtherNet/IP | Apply shows a Confirm dialog — click Confirm, then PATCH fires. On revert, no confirmation is needed |
| Redundancy protocol mode toggle | Spanning Tree (Disabled → STP/RSTP → Disabled), Turbo Ring V2 / Turbo Chain / MRP (toggle to enabled but **don't set role/config**; just global enable→disable) | Topology will re-converge briefly but mgmt link survives because we revert within seconds |

### Workarounds for pages that *look* risky but are testable

These pages were historically skipped, but they don't touch the mgmt interface or the firmware — so under the current policy they must be mutated. Use these patterns:

| Page | Workaround |
|------|-----------|
| User Accounts | Don't touch the `admin` row. Add a dummy user (e.g. `webtest` / any password meeting policy) → Apply → PATCH 200 → delete the dummy user → Apply. If the page truly offers no way to add a non-admin user, edit a harmless field on a **non-admin** existing account. |
| Online Accounts | The danger is kicking our own session. Look for a *non-current* session in the list and kick that one. If only the current session is listed, log in a second time (new tab or incognito) to create a second session, kick it from the first tab, verify PATCH 200. |
| System Time | Don't jump the wall clock — that invalidates TLS/session. DST enable↔disable and "NTP enabled" toggle are both safe mutations that produce a real PATCH. Use one of those. |
| VLAN | Never touch the mgmt VLAN. Add a dummy VLAN (e.g. VID 999) → Apply → delete it → Apply. Both PATCHes count. |
| Trusted Access | The risk is a deny-by-default rule that excludes your IP. Workaround: confirm the feature is globally **disabled** first (so the rule list has no effect), then add a dummy allow-entry for `10.99.99.99/32` → Apply → delete → Apply. If the feature is already globally enabled on the dev box, flip it off first, do the add/delete, and leave it off (or restore its prior state). |

If a page still looks like it might disconnect us after checking the above, describe the specific mechanism in the report — don't fall back to a vague "safety" skip.

### Hard-skip list — interface + firmware only

These are the *only* features that may end up GET-only. Everything else in the checklist must be mutated. Record in the report as "GET-only, mutation deliberately skipped — reason: interface-related / firmware-related".

| Category | Feature | Bucket | Reason |
|----------|---------|--------|--------|
| System | Firmware Upgrade | Firmware | Flash + reboot — disconnects entire device |
| System | Config Backup and Restore | Firmware | Restore rewrites running config / reboot |
| System | User Interface | Interface | Disabling HTTP/HTTPS/SSH kills the current browser session |
| Network Interface | Network Interface | Interface | Changing the mgmt IP/subnet disconnects |
| Security | SSH & SSL | Interface | Regenerating the HTTPS cert drops the current TLS session |

If you are tempted to add a row to this table, first verify the page is genuinely interface- or firmware-related. "Changing this breaks routing" or "this is a security page" is not sufficient — find a workaround instead.

## Known quirks on MDS/RKS dev server

Learn these — they'll save you a lot of back-and-forth:

### Session & routing

- Session silently expires during long runs. When the tab lands on `/login`, re-login and continue — don't stop.
- Navigating to an **unregistered** route (e.g. `/bfd` on MDS-L3, or `/routing-table`) redirects to `/` and then ejects the session to `/login`. This is a known UX bug. Prefer sidebar click over direct URL for routes you're not sure about.
- Sidebar items are Angular Material list items. `element.click()` via JS may not fire the router navigation — if the pathname didn't change after a JS click, fall back to a real coordinate click via `mcp__claude-in-chrome__find` + `ref` or the accessibility-tree `ref_*` from `read_page`.
- Nested sidebar groups need to be expanded step-by-step. Clicking `Routing → Unicast Route → Routing Table` in one JS call doesn't work; each click re-renders the tree, and the next `querySelectorAll` returns fresh items. Click group → `wait 1s` → click next level → `wait 1s` → click leaf.

### Network request inspection

- `mcp__claude-in-chrome__read_network_requests` with `clear: true` wipes the buffer after read. Use `clear: false` while you're still sampling, then `clear: true` at the end of a feature to reset before the next page.
- A successful save in the Moxa UI produces a PATCH to `/api/v1/setting/data/<resource>?save`. Filter with `urlPattern: "save"` to find them.
- Some saves produce a GET back on the same resource that *sometimes* returns 503 transiently (e.g., Traffic Storm Control reload). If the following GET is 200, treat it as PASS and note the transient 503.

### Known bug patterns (from prior runs on MDS-L3 2026-04-18)

If these reappear, match them against this reference before debugging from scratch:
- **Multiple Dual Homing**: `/multiple-dual-homing` unreachable — FAIL (also seen on L2/L2-4XG)
- **VRRP**: sidebar click no-op, direct URL → `/` → eject — FAIL (route missing in L3 build despite L3 supposedly supporting VRRP)
- **Routing Table / PIM-SM / BFD**: same symptom as VRRP — FAIL
- **GARP Not-installed port edit**: PATCH `stdbrgext/garpPortTable?save` returns 400, `garpPortChannelTable?save` returns 503. May be validation mismatch on not-installed ports. Flag as FAIL.
- **Ingress Rate Limit (CIR field)**: client-side validation range is 1-1000 Mbps — above that Apply stays disabled with "The valid range is from 1 to 1000"

## Report format

Write `TEST-REPORT-<APP>-<YYYY-MM-DD>.md` in the repo root. Use this layout:

```markdown
# Switch Web Functional Test Report — <APP>

- **Application**: <MODEL>
- **URL**: <URL>
- **Date**: <YYYY-MM-DD>
- **Tester**: Claude (automated sampling)
- **Mutation policy**: Every feature verified with GET + reverted mutation. Only interface- (User Interface, Network Interface, SSH & SSL) and firmware-related (Firmware Upgrade, Config Backup and Restore) pages are GET-only.
- **Source checklist**: Notion "驗證測試平行展開型號(MDS/RKS)" — <MODEL> column
- **Device**: <firmware, IP, MAC from Dashboard System Info>

## Summary

| Status | Count |
|--------|-------|
| PASS (GET + mutation verified) | X |
| PASS (GET-only — interface/firmware-related, skip allowed by policy) | X |
| FAIL (page unreachable) | X |
| FAIL (mutation returned non-2xx) | X |
| N/A per Notion ("x") | X |
| **Total** | X |

## Verified mutations

| # | Category | Feature | Route | Mutation sampled | PATCH endpoint | Result |
|---|----------|---------|-------|------------------|----------------|--------|
| ... |

## GET-only (mutation intentionally skipped)

| # | Category | Feature | Route | GET endpoints observed | Skip reason |
|---|----------|---------|-------|-----------------------|-------------|
| ... |

## FAIL

| # | Category | Feature | Symptom | Evidence |
|---|----------|---------|---------|----------|
| ... |

## Known bug regressions verified

<cross-reference each FAIL against the "Known quirks" section above>

## Recommendations

<actionable items for the dev team — group related FAILs by root cause>
```

## Browser tool loading

Deferred Chrome tools — load in bulk before starting:

```
ToolSearch with query "select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__read_network_requests,mcp__claude-in-chrome__find,mcp__claude-in-chrome__javascript_tool,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude_ai_Notion__fetch"
```

## When to stop and ask the user

- Credentials fail (neither `admin/moxa` nor any arg-provided pair work)
- Dev server tab title disagrees with `--app` in a way that suggests the user is pointing at the wrong build
- 3+ consecutive pages FAIL for the same unexplained reason
- You discover a destructive action dialog (reset to defaults, factory restore) that isn't covered by the skip list

Otherwise: **keep running until the whole checklist is done**, then write the report.
