# Project Plan: Modernize/Upgrade Active Directory Domain Controllers from Windows Server 2016

## 1) Executive Summary
This project upgrades AD Domain Controller (DC) infrastructure from Windows Server 2016 to a supported modern platform (recommended: Windows Server 2022, or 2025 if your standards and vendor stack are already validated).

Primary outcomes:
- Remove end-of-support and security risk from legacy DC OS baseline.
- Improve security posture (stronger defaults, modern crypto/TLS posture, cleaner delegation model).
- Improve resilience and recoverability through standardized builds and repeatable validation.
- Reduce operational overhead by codifying pre-check/post-check automation in PowerShell.

---

## 2) Scope
### In Scope
- AD and DNS health assessment.
- DC inventory and role mapping (FSMO, Global Catalog, DNS, Sites/Subnets).
- Build and harden new DCs on target OS.
- Join/promote new DCs; validate replication/authentication/DNS.
- Transfer/move FSMO roles (if appropriate).
- Demote/decommission Windows Server 2016 DCs.
- Documentation and runbook handoff.

### Out of Scope (unless added)
- Forest/domain functional level raises.
- PKI redesign.
- Full GPO modernization.
- AD schema extensions for new enterprise apps.
- Identity platform transformation (Entra ID hybrid redesign, etc.).

---

## 3) Recommended Target State
- **Minimum target OS**: Windows Server 2022 for all DCs.
- **Per domain/site resilience**:
  - At least two DCs per critical site.
  - Global Catalog in each major authentication site.
  - DNS integrated on all DCs unless separate enterprise DNS model exists.
- **Security baseline**:
  - Disable insecure protocols/ciphers where possible.
  - Enforce least privilege admin model for AD operations.
  - Centralized event forwarding/monitoring for DC security logs.
- **Operations**:
  - Standardized build templates.
  - Scripted validation before/after cutover.

---

## 4) Phased Project Plan & Duration Estimate
## Assumptions
- 1 forest, 1–3 domains, 4–20 DCs, moderate complexity.
- Change windows available weekly.
- No major unresolved AD replication corruption.

### Phase 0 - Discovery & Kickoff (3-5 business days)
Deliverables:
- Stakeholder matrix, change governance path.
- Current-state inventory and dependency map.
- Risk register draft.

### Phase 1 - Health Assessment & Readiness (1-2 weeks)
Activities:
- Run replication, DNS, services, event log, and SYSVOL health checks.
- Identify blockers (stale metadata, lingering objects, time skew, old agents).
- Confirm backup/restore and AD authoritative restore procedure.

Deliverables:
- Readiness report with blockers and remediation actions.
- Go/No-Go criteria.

### Phase 2 - Build & Pilot (1 week)
Activities:
- Build first wave of new DCs in pilot site.
- Promote, configure DNS/GC, validate replication and auth.
- Test pilot app/auth scenarios.

Deliverables:
- Pilot completion report.
- Updated rollout plan based on lessons learned.

### Phase 3 - Production Rollout (1-3 weeks)
Activities:
- Site-by-site DC introduction.
- FSMO migration (if needed).
- Demote legacy 2016 DCs per wave.
- Metadata cleanup and DNS/Sites and Services verification.

Deliverables:
- Migration completion by site.
- Updated CMDB/asset records.

### Phase 4 - Stabilization & Closure (3-5 business days)
Activities:
- Post-migration monitoring and tuning.
- Final compliance/security checks.
- Knowledge transfer and final documentation.

Deliverables:
- Final project closure pack and handoff.

### Typical Total Duration
- **Small environment (2-6 DCs)**: 2-4 weeks.
- **Medium environment (7-20 DCs)**: 4-8 weeks.
- **Large/complex (>20 DCs, multi-region)**: 8-16+ weeks.

---

## 5) Statements of Work (SOW) - Draft Structure
Use the companion file `SOW-Template.md` for copy/paste contract text.

### Workstream SOWs
1. **Assessment SOW**
   - Objective: determine readiness and risks.
   - Deliverable: assessment report + remediation plan.

2. **Migration SOW**
   - Objective: deploy modern DCs and retire 2016 DCs.
   - Deliverable: upgraded DC estate and signed validation checklist.

3. **Stabilization SOW**
   - Objective: ensure steady-state operations and handover.
   - Deliverable: runbook, training session, support transition.

### Acceptance Criteria (sample)
- All target DCs healthy in `dcdiag` and `repadmin`.
- No critical AD/DNS errors in event logs for agreed observation period.
- Authentication and Group Policy processing validated for representative user/device sets.
- Legacy 2016 DCs demoted/decommissioned and removed from AD metadata.

---

## 6) Potential Issues / Risks and Mitigations
1. **Replication failures pre-existing in AD**
   - Mitigation: remediate before first promotion wave; no cutover on known replication failure.

2. **DNS misconfiguration (forwarders, delegation, stale records)**
   - Mitigation: baseline DNS checks and cleanup before migration.

3. **Time synchronization drift/Kerberos failures**
   - Mitigation: validate PDC emulator time source and client sync hierarchy.

4. **Application hard-coded LDAP/DC dependencies**
   - Mitigation: dependency inventory + pilot app validation.

5. **Old antivirus/monitoring agents incompatible with new OS**
   - Mitigation: build image testing and vendor matrix validation.

6. **Firewall/site link gaps causing intermittent replication**
   - Mitigation: pre-open required ports, verify AD Sites/Subnets mapping.

7. **Rollback ambiguity**
   - Mitigation: pre-approved rollback plan per wave with clear abort thresholds.

---

## 7) Expected Wins (Business + Technical)
- Reduced security and compliance exposure from aging domain controller platform.
- Better patchability and stronger baseline controls.
- Improved AD reliability through cleanup of latent replication/DNS debt.
- Faster incident response via standardized health scripts and runbooks.
- Better audit readiness with clearer documentation and operational ownership.

---

## 8) PowerShell Automation Package (provided)
Located in `scripts/`:
- `Invoke-DCUpgradePrecheck.ps1`: pre-migration inventory + health evidence capture.
- `Invoke-DCUpgradePostcheck.ps1`: post-migration health validation and summary.

Recommended execution flow:
1. Run precheck across all sites.
2. Fix all critical findings.
3. Run pilot migration.
4. Run postcheck.
5. Repeat per rollout wave.

---

## 9) Project Governance Recommendations
- Weekly governance call (IT Ops, Security, App Owners).
- Formal Go/No-Go gate before each migration wave.
- Change records for each site cutover window.
- Daily status updates during active migration weeks.

KPIs:
- % of DCs migrated.
- Number of critical findings unresolved.
- Replication success rate.
- Authentication incident count post-cutover.

---

## 10) Recommended Next Steps
1. Approve scope and target OS standard.
2. Execute precheck scripts and review findings.
3. Finalize SOW and schedule pilot wave.
4. Run pilot and collect sign-off.
5. Execute production waves with postchecks and formal closure.
