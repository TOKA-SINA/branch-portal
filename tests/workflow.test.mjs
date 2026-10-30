import test from 'node:test';
import assert from 'node:assert/strict';
import {statuses,severities,splitIssues,compareIssues,canSeeAnalytics,normalizedStatus} from '../dist/workflow.js';
test('only the three requested statuses are offered',()=>{
 assert.deepEqual(Object.keys(statuses),['pending','current','closed']);
 assert.deepEqual(Object.values(severities),['კრიტიკული','მნიშვნელოვანი','უმნიშვნელო']);
});
test('severity outranks creation date, for internal and contractor work',()=>{
 const rows=[{number:1,severity:'minor',created_at:'2020-01-01',external_contractor:false},{number:2,severity:'critical',created_at:'2026-01-01',external_contractor:true},{number:3,severity:'important',created_at:'2025-01-01'}];
 assert.deepEqual(rows.sort(compareIssues).map(i=>i.number),[2,3,1]);
});
test('unreviewed work is kept in a separate queue',()=>{
 const rows=[{number:1,status:'current',severity:'minor',created_at:'2020-01-01'},{number:2,status:'pending',severity:null,created_at:'2026-01-01'},{number:3,status:'current',severity:'critical',created_at:'2026-02-01'},{number:4,status:'closed',severity:'important',created_at:'2025-02-01'}];
 const result=splitIssues(rows);assert.deepEqual(result.pending.map(i=>i.number),[2]);assert.deepEqual(result.ranked.map(i=>i.number),[3,4,1]);
});
test('branch analytics are disabled while manager and executor access remains',()=>{
 assert.equal(canSeeAnalytics('branch'),false);for(const role of ['admin','supervisor','executor'])assert.equal(canSeeAnalytics(role),true);
});
test('older audit statuses display through the new three-status vocabulary',()=>{
 assert.equal(normalizedStatus('awaiting_branch'),'current');assert.equal(normalizedStatus('recorded'),'closed');assert.equal(normalizedStatus('new'),'pending');
});
