-- Branch Portal: fresh project schema. Run through apply_migration.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema private revoke execute on functions from public;

create table public.branches (
 id uuid primary key default gen_random_uuid(), name text not null unique check(length(trim(name)) between 1 and 120),
 active boolean not null default true, created_at timestamptz not null default now()
);
create table public.profiles (
 id uuid primary key references auth.users(id), username text not null unique check(username ~ '^[a-z0-9][a-z0-9._-]{2,39}$'),
 display_name text not null check(length(trim(display_name)) between 1 and 120),
 role text not null check(role in ('admin','supervisor','executor','branch')),
 branch_id uuid references public.branches(id), active boolean not null default true,
 must_change_password boolean not null default true, created_at timestamptz not null default now(),
 check((role='branch')=(branch_id is not null))
);
create unique index one_account_per_branch on public.profiles(branch_id) where role='branch';
create index profiles_role_idx on public.profiles(role);
create table public.supervisor_branches (
 supervisor_id uuid not null references public.profiles(id), branch_id uuid not null references public.branches(id),
 primary key(supervisor_id,branch_id)
);
create index supervisor_branches_branch_idx on public.supervisor_branches(branch_id);
create table public.categories (
 id uuid primary key default gen_random_uuid(), name text not null unique check(length(trim(name)) between 1 and 100),
 kind text not null check(kind in ('task','record')), active boolean not null default true,
 created_at timestamptz not null default now()
);
insert into public.categories(name,kind) values ('ტექნიკური პრობლემა','task'),('იდეა','record'),('მომხმარებლის მოთხოვნა','record');
create table public.issues (
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 branch_id uuid not null references public.branches(id), category_id uuid not null references public.categories(id),
 description text not null check(length(trim(description)) between 3 and 10000),
 status text not null default 'pending' check(status in ('pending','current','closed')),
 created_by uuid not null references public.profiles(id), assigned_to uuid references public.profiles(id),
 classified_by uuid references public.profiles(id), classified_at timestamptz,
 branch_approved_at timestamptz, completed_at timestamptz, submitted_at timestamptz,
 severity text check(severity in ('minor','important','critical')),
 external_contractor boolean not null default false,
 decision_note text not null default '' check(length(decision_note)<=5000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 check(not external_contractor or assigned_to is null)
);
create index issues_branch_date_idx on public.issues(branch_id,created_at desc);
create index issues_executor_status_idx on public.issues(assigned_to,status);
create index issues_category_idx on public.issues(category_id);
create index issues_author_idx on public.issues(created_by);
create index issues_classified_by_idx on public.issues(classified_by);
create index issues_completed_idx on public.issues(completed_at) where completed_at is not null;
create index issues_external_status_idx on public.issues(status,created_at) where external_contractor and deleted_at is null;
create index issues_severity_idx on public.issues(severity,status) where deleted_at is null;
create table public.comments (
 id uuid primary key default gen_random_uuid(), issue_id uuid not null references public.issues(id),
 author_id uuid not null references public.profiles(id), body text not null check(length(trim(body)) between 1 and 5000),
 created_at timestamptz not null default now()
);
create index comments_issue_idx on public.comments(issue_id,created_at);
create index comments_author_idx on public.comments(author_id);
create table public.issue_events (
 id uuid primary key default gen_random_uuid(), issue_id uuid not null references public.issues(id),
 actor_id uuid references public.profiles(id), action text not null, detail jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index events_issue_idx on public.issue_events(issue_id,created_at);
create index events_actor_idx on public.issue_events(actor_id);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id),
 issue_id uuid not null references public.issues(id), title text not null,
 read_at timestamptz, created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications(user_id,created_at desc);
create index notifications_issue_idx on public.notifications(issue_id);
create table public.portal_setup (id boolean primary key default true check(id), token_hash text not null, claimed boolean not null default false);

create function private.my_role() returns text language sql stable security definer set search_path='' as $$
 select p.role from public.profiles p where p.id=(select auth.uid()) and p.active and auth.uid() is not null
$$;
create function private.can_manage_branch(b uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and
 (p.role='admin' or (p.role='supervisor' and exists(select 1 from public.supervisor_branches sb where sb.supervisor_id=p.id and sb.branch_id=b))))
$$;
create function private.can_read_issue(i uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.issues t join public.profiles p on p.id=auth.uid() and p.active
 where t.id=i and (p.role='admin' or (t.deleted_at is null and ((p.role='branch' and p.branch_id=t.branch_id) or
 (p.role='executor' and t.assigned_to=p.id) or (p.role='supervisor' and exists(select 1 from public.supervisor_branches sb where sb.supervisor_id=p.id and sb.branch_id=t.branch_id))))))
$$;
create function private.can_read_profile(u uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (u=auth.uid() or private.my_role()='admin' or
 (private.my_role()='supervisor' and exists(select 1 from public.profiles q where q.id=u and (q.role='executor' or
 (q.role='branch' and private.can_manage_branch(q.branch_id))))) or
 exists(select 1 from public.issues t where private.can_read_issue(t.id) and u in (t.created_by,t.assigned_to,t.classified_by)) or
 exists(select 1 from public.comments c where c.author_id=u and private.can_read_issue(c.issue_id)) or
 exists(select 1 from public.issue_events e where e.actor_id=u and private.can_read_issue(e.issue_id)))
$$;
grant execute on function private.my_role(),private.can_manage_branch(uuid),private.can_read_issue(uuid),private.can_read_profile(uuid) to authenticated;

alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.supervisor_branches enable row level security;
alter table public.categories enable row level security;
alter table public.issues enable row level security;
alter table public.comments enable row level security;
alter table public.issue_events enable row level security;
alter table public.notifications enable row level security;
alter table public.portal_setup enable row level security;
revoke all on all tables in schema public from anon,authenticated;
grant select on public.branches,public.profiles,public.supervisor_branches,public.categories,public.issues,public.comments,public.issue_events,public.notifications to authenticated;
grant insert,update on public.branches,public.categories,public.issues to authenticated;
grant insert,delete on public.supervisor_branches to authenticated;
grant insert on public.comments to authenticated;
grant update(read_at) on public.notifications to authenticated;
grant usage,select on sequence public.issues_number_seq to authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;

create policy branches_read on public.branches for select to authenticated using (
 private.can_manage_branch(id) or id=(select p.branch_id from public.profiles p where p.id=(select auth.uid())) or
 exists(select 1 from public.issues t where t.branch_id=branches.id and t.assigned_to=(select auth.uid()))
);
create policy branches_insert on public.branches for insert to authenticated with check((select private.my_role())='admin');
create policy branches_update on public.branches for update to authenticated using((select private.my_role())='admin') with check((select private.my_role())='admin');
create policy profiles_read on public.profiles for select to authenticated using(private.can_read_profile(id));
create policy supervisor_scope_read on public.supervisor_branches for select to authenticated using((select private.my_role())='admin' or supervisor_id=(select auth.uid()));
create policy supervisor_scope_insert on public.supervisor_branches for insert to authenticated with check((select private.my_role())='admin');
create policy supervisor_scope_delete on public.supervisor_branches for delete to authenticated using((select private.my_role())='admin');
create policy categories_read on public.categories for select to authenticated using((select private.my_role()) is not null);
create policy categories_insert on public.categories for insert to authenticated with check((select private.my_role())='admin');
create policy categories_update on public.categories for update to authenticated using((select private.my_role())='admin') with check((select private.my_role())='admin');
create policy issues_read on public.issues for select to authenticated using ((select private.my_role())='admin' or (deleted_at is null and (((select private.my_role())='branch' and branch_id=(select p.branch_id from public.profiles p where p.id=(select auth.uid()))) or ((select private.my_role())='executor' and assigned_to=(select auth.uid())) or private.can_manage_branch(branch_id))));
create policy issues_insert on public.issues for insert to authenticated with check((select private.my_role())='admin' or
 ((select private.my_role())='branch' and branch_id=(select p.branch_id from public.profiles p where p.id=(select auth.uid())) and created_by=(select auth.uid())));
create policy issues_update on public.issues for update to authenticated using(private.can_read_issue(id)) with check(private.can_read_issue(id));
create policy comments_read on public.comments for select to authenticated using(private.can_read_issue(issue_id));
create policy comments_insert on public.comments for insert to authenticated with check(author_id=(select auth.uid()) and (select private.my_role()) in ('admin','supervisor','executor') and private.can_read_issue(issue_id));
create policy events_read on public.issue_events for select to authenticated using(private.can_read_issue(issue_id));
create policy notifications_read on public.notifications for select to authenticated using(user_id=(select auth.uid()) and private.can_read_issue(issue_id));
create policy notifications_update on public.notifications for update to authenticated using(user_id=(select auth.uid()) and private.can_read_issue(issue_id)) with check(user_id=(select auth.uid()) and private.can_read_issue(issue_id));
create policy setup_service_only on public.portal_setup to service_role using(true) with check(true);

create function private.validate_scope() returns trigger language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=new.supervisor_id and role='supervisor' and active) then raise exception 'ვაიზერი არასწორად არის არჩეული'; end if;
 return new;
end $$;
create trigger validate_supervisor_scope before insert or update on public.supervisor_branches for each row execute function private.validate_scope();

create function private.guard_issue() returns trigger language plpgsql security definer set search_path='' as $$
declare
 r text:=private.my_role();uid uuid:=auth.uid();k text;manager boolean;
 wanted_status text:=new.status;wanted_severity text:=new.severity;wanted_to uuid:=new.assigned_to;
 wanted_external boolean:=new.external_contractor;wanted_submitted timestamptz:=new.submitted_at;
 category_changed boolean:=false;branch_changed boolean:=false;target_changed boolean:=false;
begin
 if uid is null or r is null then raise exception 'ავტორიზაცია აუცილებელია';end if;
 select kind into k from public.categories where id=new.category_id;
 if tg_op='INSERT' then
  if r not in ('admin','branch') then raise exception 'საკითხის შექმნის უფლება არ გაქვთ';end if;
  if not exists(select 1 from public.branches where id=new.branch_id and active) then raise exception 'ფილიალი არააქტიურია';end if;
  if not exists(select 1 from public.categories where id=new.category_id and active) then raise exception 'კატეგორია არააქტიურია';end if;
  if r='branch' and new.branch_id is distinct from (select branch_id from public.profiles where id=uid) then raise exception 'სხვა ფილიალი მიუწვდომელია';end if;
  new.created_by:=uid;new.created_at:=now();new.updated_at:=now();new.status:='pending';
  new.assigned_to:=null;new.external_contractor:=false;new.severity:=null;
  new.classified_by:=null;new.classified_at:=null;new.branch_approved_at:=null;new.completed_at:=null;
  new.submitted_at:=null;new.deleted_at:=null;new.decision_note:='';return new;
 end if;
 if new.id<>old.id or new.number<>old.number or new.created_by<>old.created_by or new.created_at<>old.created_at then raise exception 'სისტემური ველები უცვლელია';end if;
 if r='branch' then raise exception 'ფილიალს დაფიქსირებული საკითხის შეცვლა არ შეუძლია';end if;
 if r<>'admin' and (new.description is distinct from old.description or new.branch_id<>old.branch_id or new.deleted_at is distinct from old.deleted_at) then raise exception 'რედაქტირება მხოლოდ ადმინს შეუძლია';end if;
 if old.deleted_at is not null and r<>'admin' then raise exception 'საკითხი წაშლილია';end if;
 category_changed:=new.category_id is distinct from old.category_id;
 branch_changed:=new.branch_id is distinct from old.branch_id;
 target_changed:=wanted_to is distinct from old.assigned_to or wanted_external is distinct from old.external_contractor;
 manager:=r='admin' or (r='supervisor' and private.can_manage_branch(old.branch_id));
 new.classified_by:=old.classified_by;new.classified_at:=old.classified_at;new.completed_at:=old.completed_at;
 new.submitted_at:=old.submitted_at;new.branch_approved_at:=old.branch_approved_at;
 if r='executor' then
  if old.assigned_to is distinct from uid or old.external_contractor or old.status<>'current' or old.deleted_at is not null then raise exception 'ამ საკითხზე შესრულების მონიშვნის უფლება არ გაქვთ';end if;
  if category_changed or branch_changed or target_changed or wanted_severity is distinct from old.severity or wanted_status<>'current' then raise exception 'შემსრულებელს მხოლოდ შესრულების მონიშვნა შეუძლია';end if;
  if old.submitted_at is not null or wanted_submitted is null then raise exception 'შესრულება უკვე მონიშნულია ან მოთხოვნა არასწორია';end if;
  new.submitted_at:=now();new.updated_at:=now();return new;
 end if;
 if not manager then raise exception 'საკითხის მართვის უფლება არ გაქვთ';end if;
 if r='admin' and not category_changed and not branch_changed and not target_changed and wanted_status=old.status and wanted_severity is not distinct from old.severity and wanted_submitted is not distinct from old.submitted_at then
  new.updated_at:=now();return new;
 end if;
 if category_changed and not exists(select 1 from public.categories where id=new.category_id and active) then raise exception 'კატეგორია არააქტიურია';end if;
 if branch_changed and not exists(select 1 from public.branches where id=new.branch_id and active) then raise exception 'ფილიალი არააქტიურია';end if;
 if category_changed or branch_changed then
  new.status:='pending';new.severity:=null;new.assigned_to:=null;new.external_contractor:=false;
  new.classified_by:=null;new.classified_at:=null;new.completed_at:=null;new.submitted_at:=null;new.branch_approved_at:=null;
 end if;
 if wanted_status='pending' and (old.status='pending' or category_changed or branch_changed or r='admin') then
  new.status:='pending';new.severity:=null;new.assigned_to:=null;new.external_contractor:=false;
  new.classified_at:=null;new.classified_by:=null;new.submitted_at:=null;new.branch_approved_at:=null;new.completed_at:=null;new.decision_note:='';
 elsif k='record' and wanted_status='closed' and (old.status in ('pending','current') or category_changed or branch_changed) then
  new.status:='closed';new.severity:=null;new.assigned_to:=null;new.external_contractor:=false;
  new.classified_by:=uid;new.classified_at:=now();new.completed_at:=now();new.submitted_at:=null;new.branch_approved_at:=null;new.decision_note:='';
 elsif k='task' and wanted_status='current' and (old.status in ('pending','current') or category_changed or branch_changed) then
  if wanted_severity is null or wanted_severity not in ('minor','important','critical') then raise exception 'გადაცემამდე აირჩიეთ საკითხის სიმძიმე';end if;
  if wanted_external then new.assigned_to:=null;
  else
   if wanted_to is null or not exists(select 1 from public.profiles where id=wanted_to and role='executor' and active) then raise exception 'აირჩიეთ აქტიური შემსრულებელი ან გარე კონტრაქტორი';end if;
   new.assigned_to:=wanted_to;
  end if;
  new.external_contractor:=wanted_external;new.severity:=wanted_severity;new.status:='current';new.completed_at:=null;new.branch_approved_at:=null;
  if old.status='pending' or category_changed or branch_changed then
   if not exists(select 1 from public.categories where id=new.category_id and active) then raise exception 'კატეგორია არააქტიურია';end if;
   new.classified_by:=uid;new.classified_at:=now();new.submitted_at:=null;new.decision_note:='';
  elsif target_changed then
   if old.submitted_at is not null and length(trim(new.decision_note))<3 then raise exception 'ხელახალ გადაცემამდე მიუთითეთ დაბრუნების მიზეზი';end if;
   new.submitted_at:=null;
  elsif old.submitted_at is not null and wanted_submitted is null then
   if length(trim(new.decision_note))<3 then raise exception 'უარის მიზეზი სავალდებულოა';end if;
   new.submitted_at:=null;
  elsif old.submitted_at is null and wanted_submitted is not null then
   if r<>'admin' or old.external_contractor then raise exception 'შიდა დავალების შესრულებას შემსრულებელი მონიშნავს';end if;
   new.submitted_at:=now();
  else new.decision_note:='';end if;
 elsif k='task' and wanted_status='closed' and old.status='current' and not category_changed and not branch_changed then
  if target_changed or wanted_severity is distinct from old.severity then raise exception 'ჯერ შეინახეთ დანიშვნის ცვლილება';end if;
  if not old.external_contractor and old.submitted_at is null then raise exception 'შემსრულებელმა ჯერ უნდა მონიშნოს შესრულება';end if;
  new.status:='closed';new.completed_at:=now();new.branch_approved_at:=null;new.decision_note:='';
 elsif wanted_status='closed' and old.status='closed' and not category_changed and not branch_changed then
  if target_changed or wanted_severity is distinct from old.severity or wanted_submitted is distinct from old.submitted_at then raise exception 'დახურული საკითხის დანიშვნა უცვლელია';end if;
 else raise exception 'სტატუსის ამგვარი შეცვლა დაუშვებელია';end if;
 new.updated_at:=now();return new;
end $$;

create trigger guard_issue before insert or update on public.issues for each row execute function private.guard_issue();

create function private.issue_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare label text;act text;event_note text:='';
begin
 if auth.uid() is null then raise exception 'ავტორიზაცია აუცილებელია';end if;
 if tg_op='INSERT' then label:='ახალი საკითხი — ვაიზერის დასადასტურებელი';act:='created';
 elsif new.deleted_at is distinct from old.deleted_at then label:=case when new.deleted_at is null then 'საკითხი აღდგენილია' else 'საკითხი წაშლილია' end;act:='visibility';
 elsif new.category_id is distinct from old.category_id then label:='კატეგორია შეიცვალა';act:='category';
 elsif new.submitted_at is not null and old.submitted_at is null then label:='შემსრულებელმა შესრულება მონიშნა';act:='submitted';event_note:=new.decision_note;
 elsif old.submitted_at is not null and new.submitted_at is null and new.status='current' then label:='შესრულება დაბრუნებულია';act:='returned';event_note:=new.decision_note;
 elsif new.assigned_to is distinct from old.assigned_to or new.external_contractor is distinct from old.external_contractor then
  label:=case when new.external_contractor then 'გარე კონტრაქტორთან გადაცემულია' else 'დავალება გადაეცა შემსრულებელს' end;act:='assignment';event_note:=new.decision_note;
 elsif new.status is distinct from old.status then
  label:=case new.status when 'closed' then 'საკითხი დახურულია' when 'current' then 'საკითხი დადასტურებულია და მიმდინარეა' else 'საკითხი ვაიზერის დასადასტურებელია' end;act:='status';
 elsif new.severity is distinct from old.severity then label:='საკითხის სიმძიმე შეიცვალა';act:='severity';
 elsif new.description is distinct from old.description or new.branch_id is distinct from old.branch_id then label:='საკითხი რედაქტირებულია';act:='edited';
 else return new;end if;
 insert into public.issue_events(issue_id,actor_id,action,detail) values(new.id,auth.uid(),act,jsonb_build_object('label',label,'status',new.status,'severity',new.severity,'external_contractor',new.external_contractor,'category_id',new.category_id,'assigned_to',new.assigned_to,'note',event_note,'previous',case when tg_op='UPDATE' then jsonb_build_object('status',old.status,'severity',old.severity,'external_contractor',old.external_contractor,'category_id',old.category_id,'assigned_to',old.assigned_to,'description',old.description) else null end));
 insert into public.notifications(user_id,issue_id,title)
 select distinct p.id,new.id,label||' · #'||new.number from public.profiles p where p.active and p.id<>auth.uid() and
 (p.role='admin' or (p.role='branch' and p.branch_id=new.branch_id) or
 (p.role='supervisor' and exists(select 1 from public.supervisor_branches sb where sb.supervisor_id=p.id and sb.branch_id=new.branch_id)) or
 (p.role='executor' and not new.external_contractor and p.id=new.assigned_to));
 return new;
end $$;

create trigger issue_activity after insert or update on public.issues for each row execute function private.issue_activity();

create function private.comment_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare t public.issues;
begin
 if auth.uid() is null or new.author_id<>auth.uid() or private.my_role() not in ('admin','supervisor','executor') or not private.can_read_issue(new.issue_id) then raise exception 'კომენტარის უფლება არ გაქვთ';end if;
 select * into t from public.issues where id=new.issue_id;
 if t.deleted_at is not null then raise exception 'საკითხი წაშლილია';end if;
 new.created_at:=now();
 insert into public.notifications(user_id,issue_id,title)
 select distinct p.id,t.id,'ახალი კომენტარი · #'||t.number from public.profiles p where p.active and p.id<>auth.uid() and
 (p.role='admin' or (p.role='branch' and p.branch_id=t.branch_id) or
 (p.role='supervisor' and exists(select 1 from public.supervisor_branches sb where sb.supervisor_id=p.id and sb.branch_id=t.branch_id)) or p.id=t.assigned_to);
 return new;
end $$;
create trigger comment_activity before insert on public.comments for each row execute function private.comment_activity();

-- Bootstrap is callable only by the server's service role, never by a browser client.
create function public.claim_portal_setup(p_hash text) returns boolean language plpgsql security invoker set search_path='' as $$
declare changed integer;
begin
 update public.portal_setup set claimed=true where id=true and not claimed and token_hash=p_hash;
 get diagnostics changed=row_count;return changed=1;
end $$;
revoke all on function public.claim_portal_setup(text) from public,anon,authenticated;
grant execute on function public.claim_portal_setup(text) to service_role;
revoke all on all functions in schema private from public,anon;
