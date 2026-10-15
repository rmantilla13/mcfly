-- Accounts: a profile per person, the first person to sign up owns McFly,
-- displays get neither.
\set ON_ERROR_STOP 1
\set first  'a0000000-0000-0000-0000-000000000001'
\set second 'a0000000-0000-0000-0000-000000000002'
\set device 'd0000000-0000-0000-0000-000000000001'

insert into auth.users (id, email, raw_user_meta_data) values (:'first', 'ricky@example.com', '{"display_name": " Ricky "}');
select tests.eq((select display_name from profiles where id = :'first'), 'Ricky', 'profile from the sign-up name');
select tests.eq((select count(*)::int from platform_admins where user_id = :'first'), 1, 'the first person is the admin');

insert into auth.users (id, email, raw_app_meta_data) values (:'device', 'device-1@devices.mcfly.invalid', '{"kind": "device"}');
select tests.eq((select count(*)::int from profiles where id = :'device'), 0, 'a display gets no profile');
select tests.eq((select count(*)::int from platform_admins), 1, 'and is never an admin');

insert into auth.users (id, email) values (:'second', 'friend@example.com');
select tests.eq((select display_name from profiles where id = :'second'), 'friend', 'profile from the email');
select tests.eq((select count(*)::int from platform_admins), 1, 'the second person is not an admin');

select tests.login(:'second');
select tests.eq((select count(*)::int from profiles), 1, 'a person sees only their own profile');
select tests.eq(tests.affected($$update profiles set display_name = 'Friend' where id = 'a0000000-0000-0000-0000-000000000002'$$), 1, 'and edits it');
select tests.eq(tests.affected($$update profiles set display_name = 'x' where id = 'a0000000-0000-0000-0000-000000000001'$$), 0, 'but not another');
select tests.ok(not can_read(), 'a person without admin rights reads no feeds');
select tests.login(:'first');
select tests.eq((select count(*)::int from profiles), 2, 'the admin sees every profile');
select admin_set_admin(:'second', true);
select tests.login(:'second');
select tests.ok(can_read(), 'once added, they read the feeds');
