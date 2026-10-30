export const statuses={pending:'ვაიზერის დასადასტურებელი',current:'მიმდინარე',closed:'დახურული'};
export const severities={critical:'კრიტიკული',important:'მნიშვნელოვანი',minor:'უმნიშვნელო'};
const rank={critical:3,important:2,minor:1};
const stateRank={current:2,closed:1,pending:0};
const oldStatuses={new:'pending',pending_assignment:'pending',assigned:'current',in_progress:'current',awaiting_branch:'current',awaiting_supervisor:'current',returned:'current',completed:'closed',recorded:'closed'};
export const normalizedStatus=value=>oldStatuses[value]||value;
export const canSeeAnalytics=role=>['admin','supervisor','executor'].includes(role);
export function compareIssues(a,b){return (stateRank[normalizedStatus(b.status)]??2)-(stateRank[normalizedStatus(a.status)]??2)||(rank[b.severity]||0)-(rank[a.severity]||0)||new Date(a.created_at)-new Date(b.created_at)||Number(a.number)-Number(b.number)}
export function splitIssues(rows){return {pending:rows.filter(i=>normalizedStatus(i.status)==='pending').sort((a,b)=>new Date(a.created_at)-new Date(b.created_at)),ranked:rows.filter(i=>normalizedStatus(i.status)!=='pending').sort(compareIssues)}}
