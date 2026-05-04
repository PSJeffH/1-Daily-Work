# Statement of Work (SOW) Template - Domain Controller Upgrade from Windows Server 2016

## 1. Overview
This Statement of Work defines professional services to assess, migrate, and stabilize Active Directory Domain Controllers currently on Windows Server 2016.

## 2. Objectives
- Migrate DC workloads to approved target OS (Server 2022/2025 per client standard).
- Maintain authentication, DNS, and replication service continuity.
- Retire legacy Server 2016 DCs with proper decommissioning.

## 3. Scope of Services
### 3.1 Assessment
- Current-state discovery and inventory.
- AD/DNS health checks and risk analysis.
- Migration wave design.

### 3.2 Implementation
- Build/harden target OS DC servers.
- Join/promote and validate new DCs.
- Transfer FSMO roles as required.
- Demote/decommission Server 2016 DCs.

### 3.3 Stabilization
- Post-migration monitoring period.
- Incident support and tuning.
- Knowledge transfer and final documentation.

## 4. Deliverables
- Assessment report and remediation tracker.
- Migration runbook and rollout calendar.
- Validation evidence package (pre/post checks).
- Final as-built documentation and handoff.

## 5. Assumptions
- Customer provides required access, approvals, and maintenance windows.
- Network/firewall dependencies can be modified within project timeline.
- Backup and recovery controls exist and are tested.

## 6. Exclusions
- Forest redesign.
- Identity architecture transformation beyond DC OS upgrade.
- Major app remediation unrelated to AD/DC upgrade.

## 7. Roles and Responsibilities
### Service Provider
- Execute technical tasks and provide status reporting.
- Maintain risk/issue log and escalation communication.

### Customer
- Provide decision-makers and approvers.
- Coordinate app owner testing and sign-off.
- Maintain change management tickets.

## 8. Timeline (sample)
- Week 1: Discovery and assessment.
- Week 2: Remediation and pilot.
- Weeks 3-5: Production waves.
- Week 6: Stabilization and closure.

## 9. Acceptance Criteria
- Target DCs pass agreed health checks (`dcdiag`, `repadmin`, DNS tests).
- No critical Sev-1/Sev-2 issues attributable to migration at closure.
- Legacy 2016 DCs demoted and removed from active service.
- Customer sign-off on closure report.

## 10. Risks and Dependencies
- Replication instability.
- DNS architecture debt.
- Site/network latency or blocked ports.
- Untracked legacy application dependencies.

## 11. Commercials (to be completed)
- Pricing model (fixed fee / T&M).
- Milestone payment schedule.
- Travel/expense assumptions.

## 12. Change Control
Any scope modifications must be documented and approved through formal change request before execution.
