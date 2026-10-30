-- Run against a configured portal as project owner. All fixtures roll back.
begin;
create temporary table qa_workflow as select
 (select id from public.profiles where role='admin' and active limit 1) as admin_id,
 (select id from public.profiles where role='supervisor' and active limit 1) as supervisor_id,
 (select id from public.profiles where role='executor' and active limit 1) as executor_id,
 (select id from public.profiles where role='branch' and active limit 1) as branch_user,
 (select branch_id from public.profiles where role='branch' and active limit 1) as branch_id,
 (select id from public.categories where kind='task' and active limit 1) as task_category,
 (select id from public.categories where kind='record' and active limit 1) as record_category,
 gen_random_uuid() as internal_issue,gen_random_uuid() as external_issue,gen_random_uuid() as record_issue,
 gen_random_uuid() as other_issue,gen_random_uuid() as other_branch;
do $$ begin assert (select admin_id is not null and supervisor_id is not null and executor_id is not null and branch_user is not null and task_category is not null and record_category is not null from qa_workflow),'Test requires one active account per role and task/record categories';end $$;
insert into public.supervisor_branches(supervisor_id,branch_id) select supervisor_id,branch_id from qa_workflow on conflict do nothing;
insert into public.branches(id,name) select other_branch,'QA workflow rollback '||other_branch from qa_workflow;
grant select on qa_workflow to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('sub',(select branch_user from qa_workflow),'role','authenticated')::text,true);
insert into public.issues(id,branch_id,category_id,description,created_by,status,severity,external_contractor,assigned_to)
select internal_issue,branch_id,task_category,'QA rollback internal issue',branch_user,'closed','critical',true,executor_id from qa_workflow;
insert into public.issues(id,branch_id,category_id,description,created_by)
select external_issue,branch_id,task_category,'QA rollback external issue',branch_user from qa_workflow;
insert into public.issues(id,branch_id,category_id,description,created_by)
select record_issue,branch_id,record_category,'QA rollback idea',branch_user from qa_workflow;
do $$ declare t public.issues;denied boolean:=false;begin
 select * into t from public.issues where id=(select internal_issue from qa_workflow);
 assert t.status='pending' and t.severity is null and t.assigned_to is null and not t.external_contractor,'Branch creation cannot spoof approval, priority or assignment';
 begin update public.issues set severity='critical' where id=t.id;exception when others then denied:=true;end;
 assert denied,'Branch cannot set severity';
end $$;
select set_config('request.jwt.claims',json_build_object('sub',(select admin_id from qa_workflow),'role','authenticated')::text,true);
insert into public.issues(id,branch_id,category_id,description,created_by)
select other_issue,other_branch,task_category,'QA rollback unallocated contractor',admin_id from qa_workflow;
update public.issues set status='current',severity='critical',external_contractor=true where id=(select other_issue from qa_workflow);
select set_config('request.jwt.claims',json_build_object('sub',(select supervisor_id from qa_workflow),'role','authenticated')::text,true);
do $$ declare denied boolean:=false;begin
 assert (select count(*) from public.issues where id=(select other_issue from qa_workflow))=0,'Supervisor cannot read unallocated contractor work';
 begin update public.issues set status='current',assigned_to=(select executor_id from qa_workflow) where id=(select internal_issue from qa_workflow);exception when others then denied:=true;end;
 assert denied,'Assignment requires severity';denied:=false;
 begin update public.issues set status='current',severity='important' where id=(select internal_issue from qa_workflow);exception when others then denied:=true;end;
 assert denied,'Internal work requires an executor';
end $$;
update public.issues set status='current',severity='minor',assigned_to=(select executor_id from qa_workflow) where id=(select internal_issue from qa_workflow);
do $$ declare denied boolean:=false;begin
 begin update public.issues set status='closed' where id=(select internal_issue from qa_workflow);exception when others then denied:=true;end;
 assert denied,'Supervisor cannot close internal work before executor submission';
end $$;
update public.issues set status='current',severity='critical',external_contractor=true where id=(select external_issue from qa_workflow);
update public.issues set status='closed',severity='critical',external_contractor=true,assigned_to=(select executor_id from qa_workflow) where id=(select record_issue from qa_workflow);
do $$ declare t public.issues;denied boolean:=false;begin
 select * into t from public.issues where id=(select record_issue from qa_workflow);
 assert t.status='closed' and t.completed_at is not null and t.severity is null and t.assigned_to is null and not t.external_contractor,'Record approval closes without severity or assignment';
 begin update public.issues set status='current',severity='minor',assigned_to=(select executor_id from qa_workflow) where id=t.id;exception when others then denied:=true;end;
 assert denied,'Records cannot be assigned as tasks';
end $$;
select set_config('request.jwt.claims',json_build_object('sub',(select executor_id from qa_workflow),'role','authenticated')::text,true);
do $$ declare denied boolean:=false;begin
 assert (select count(*) from public.issues where id=(select internal_issue from qa_workflow))=1,'Executor reads assigned internal work';
 assert (select count(*) from public.issues where id=(select external_issue from qa_workflow))=0,'Executor cannot see contractor work';
 begin update public.issues set status='closed' where id=(select internal_issue from qa_workflow);exception when others then denied:=true;end;
 assert denied,'Executor cannot close';denied:=false;
 begin update public.issues set severity='critical',submitted_at=now() where id=(select internal_issue from qa_workflow);exception when others then denied:=true;end;
 assert denied,'Executor cannot change severity';
end $$;
update public.issues set submitted_at=now(),decision_note='QA submitted' where id=(select internal_issue from qa_workflow);
do $$ begin assert (select status='current' and submitted_at is not null and completed_at is null from public.issues where id=(select internal_issue from qa_workflow)),'Submission keeps current status';end $$;
select set_config('request.jwt.claims',json_build_object('sub',(select branch_user from qa_workflow),'role','authenticated')::text,true);
do $$ declare denied boolean:=false;begin
 begin update public.issues set status='closed' where id=(select internal_issue from qa_workflow);exception when others then denied:=true;end;
 assert denied,'Branch has no approval or closing action';
end $$;
select set_config('request.jwt.claims',json_build_object('sub',(select supervisor_id from qa_workflow),'role','authenticated')::text,true);
do $$ declare denied boolean:=false;begin
 begin update public.issues set submitted_at=null,decision_note='' where id=(select internal_issue from qa_workflow);exception when others then denied:=true;end;
 assert denied,'Rejecting executor submission requires a reason';
end $$;
update public.issues set submitted_at=null,decision_note='QA needs another repair' where id=(select internal_issue from qa_workflow);
do $$ begin assert (select status='current' and submitted_at is null from public.issues where id=(select internal_issue from qa_workflow)),'Rejection keeps current and clears submission';end $$;
select set_config('request.jwt.claims',json_build_object('sub',(select executor_id from qa_workflow),'role','authenticated')::text,true);
update public.issues set submitted_at=now(),decision_note='QA repaired' where id=(select internal_issue from qa_workflow);
select set_config('request.jwt.claims',json_build_object('sub',(select supervisor_id from qa_workflow),'role','authenticated')::text,true);
update public.issues set status='closed' where id=(select internal_issue from qa_workflow);
update public.issues set status='closed' where id=(select external_issue from qa_workflow);
do $$ begin
 assert (select status='closed' and completed_at is not null and branch_approved_at is null from public.issues where id=(select internal_issue from qa_workflow)),'Internal closure needs no branch approval';
 assert (select status='closed' and external_contractor and assigned_to is null and submitted_at is null and completed_at is not null from public.issues where id=(select external_issue from qa_workflow)),'Supervisor directly closes contractor work';
 assert (select count(*) from public.issue_events where issue_id=(select external_issue from qa_workflow) and detail->>'external_contractor'='true')>0,'Contractor changes are audited';
end $$;
select set_config('request.jwt.claims',json_build_object('sub',(select admin_id from qa_workflow),'role','authenticated')::text,true);
update public.issues set deleted_at=now() where id=(select internal_issue from qa_workflow);
update public.issues set deleted_at=null,description='QA rollback edited' where id=(select internal_issue from qa_workflow);
do $$ begin assert (select status='closed' and deleted_at is null and description='QA rollback edited' from public.issues where id=(select internal_issue from qa_workflow)),'Admin edits, deletes and restores without reopening';end $$;
rollback;
select 'WORKFLOW_V2_ROLE_AND_TRANSITION_TESTS_PASSED; all fixtures rolled back' as result;
