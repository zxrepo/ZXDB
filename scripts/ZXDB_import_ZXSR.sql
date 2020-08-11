-- [ZXDB] Import Chris Bourne's ZXSR tables into ZXDB
-- by Einar Saukas

USE zxdb;

-- Remove old data
drop table if exists zxsr_captions;
drop table if exists zxsr_scores;
drop table if exists zxsr_reviews;
drop table if exists tmp_reviews;
drop table if exists tmp_issues;
drop table if exists tmp_magazines;

-- Map SSD_Magazines(mag_id) from/to ZXDB.magazines(id)
create table tmp_magazines(
  ssd_mag_id INT(11) NOT NULL primary key,
  magazine_id SMALLINT(6) not null,
  foreign key fk_tmp_magazine (magazine_id) references magazines(id),
  foreign key fk_tmp_ssd_magazine (ssd_mag_id) references ssd.ssd_magazines(mag_id)
);

insert into tmp_magazines(ssd_mag_id, magazine_id) (
  select s.mag_id,m.id from ssd.ssd_magazines s inner join magazines m on
  lower(replace(replace(replace(s.mag_name,
  'Which Micro Software Review','Which Micro? & Software Review'),
  'ACE','ACE (Advanced Computer Entertainment)'),
  'Computer & Videogames','C&VG (Computer & Video Games)')
  ) = lower(m.name) where 1=1);

select * from ssd.ssd_magazines where mag_id not in (select ssd_mag_id from tmp_magazines);
select * from ssd.ssd_issues s where s.mag_id not in (select ssd_mag_id from tmp_magazines);
select * from ssd.ssd_reviewers r where r.MagazineId not in (select ssd_mag_id from tmp_magazines);
select * from ssd.ssd_lookreviewaward r where r.mag_type not in (select ssd_mag_id from tmp_magazines);

-- Map SSD_Issues(IssueCode) from/to ZXDB.issues(id)
create table tmp_issues(
  ssd_issuecode INT(11) NOT NULL primary key,
  issue_id INT(11) not null,
  foreign key fk_tmp_issue (issue_id) references issues(id),
  foreign key fk_tmp_ssd_issue (ssd_issuecode) references ssd.ssd_issues(IssueCode)
);

insert into tmp_issues(ssd_issuecode, issue_id) values
((select s.IssueCode from ssd.ssd_issues s inner join ssd.ssd_magazines m on m.mag_id=s.mag_id where s.Issue = '1984 Annual' and m.mag_name = 'Sinclair User Annual'),(select i.id from issues i inner join magazines m on i.magazine_id = m.id where m.name = 'Sinclair User Annual' and i.date_year = 1984)),
((select s.IssueCode from ssd.ssd_issues s inner join ssd.ssd_magazines m on m.mag_id=s.mag_id where s.Issue = 'Issue December 1984' and m.mag_name = 'ZX Collection'),(select i.id from issues i inner join magazines m on i.magazine_id = m.id where m.name = 'ZX Collection' and i.date_year = 1984));

insert into tmp_issues(ssd_issuecode, issue_id) (select s.IssueCode,i.id from ssd.ssd_issues s inner join tmp_magazines t on t.ssd_mag_id = s.mag_id inner join issues i on i.magazine_id = t.magazine_id and s.Issue = concat('Issue ',i.number,', ',MONTHNAME(STR_TO_DATE(i.date_month, '%m')),' ',i.date_year) where i.date_year is not null and i.date_month is not null and i.number is not null);

insert into tmp_issues(ssd_issuecode, issue_id) (select s.IssueCode,i.id from ssd.ssd_issues s inner join tmp_magazines t on t.ssd_mag_id = s.mag_id inner join issues i on i.magazine_id = t.magazine_id and s.Issue = concat('Issue 0',i.number,', ',MONTHNAME(STR_TO_DATE(i.date_month, '%m')),' ',i.date_year) where i.date_year is not null and i.date_month is not null and i.number is not null);

insert into tmp_issues(ssd_issuecode, issue_id) (select s.IssueCode,i.id from ssd.ssd_issues s inner join tmp_magazines t on t.ssd_mag_id = s.mag_id inner join issues i on i.magazine_id = t.magazine_id and s.Issue = concat('Issue ',MONTHNAME(STR_TO_DATE(i.date_month, '%m')),' ',i.date_year) where i.date_year is not null and i.date_month is not null and s.IssueCode not in (select ssd_issuecode from tmp_issues));

insert into tmp_issues(ssd_issuecode, issue_id) (select s.IssueCode,i.id from ssd.ssd_issues s inner join tmp_magazines t on t.ssd_mag_id = s.mag_id inner join issues i on i.magazine_id = t.magazine_id and i.number = substring(substring_index(s.Issue,',',1),7) where s.Issue like 'Issue %,%' and s.IssueCode not in (select ssd_issuecode from tmp_issues));

select * from ssd.ssd_issues r where r.IssueCode not in (select t.ssd_issuecode from tmp_issues t);
select * from ssd.ssd_reviews r where r.issue_code not in (select t.ssd_issuecode from tmp_issues t);

-- Build a ZXDB-friendly version of SSD_Reviews
create table tmp_reviews (
    id int(11) not null primary key,
    entry_id int(11) not null,
    issue_id int(11) not null,
    page smallint(6) not null,
    is_supplement tinyint(1) not null,
    mag_section varchar(50),
    review_text longtext,
    review_comments longtext,
    review_rating longtext,
    reviewers longtext,
    award_id tinyint(4),
    score_group varchar(100) not null default '',
    variant tinyint(4) not null default 0,
    parent_id int(11),
    magref_id int(11),
    prefix_review_text varchar(100) not null default '',
    constraint fk_tmp_review_entry foreign key (entry_id) references entries(id),
    constraint fk_tmp_review_issue foreign key (issue_id) references issues(id),
    constraint fk_tmp_review_award foreign key (award_id) references zxsr_awards(id),
    constraint fk_tmp_review_parent foreign key (parent_id) references tmp_reviews(id),
    constraint fk_tmp_review_magref foreign key (magref_id) references magrefs(id),
    index ix_tmp_text(prefix_review_text)
);

insert into tmp_reviews(id, entry_id, issue_id, page, is_supplement, mag_section, review_text, review_comments, review_rating, reviewers, award_id) (
select s.review_id, g.WOSID, i.issue_id,
nullif(trim(substring_index(replace(replace(s.review_page,'(Supplement)',''),'.',','),',',1)),''),
if (s.review_page like '%(Supplement)',1,0),
m.mag_name,
nullif(replace(s.review_text,'\r\n','#'),''),
nullif(replace(replace(s.review_comments,'\r\n','#'),'¬','####'),''),
nullif(replace(s.review_rating,'\r\n','#'),''),
nullif(s.reviewers,''),
if (s.award_id<>999,s.award_id,null)
from ssd.ssd_reviews s
left join ssd.ssd_game g on g.ID = s.game_id
left join tmp_issues i on s.issue_code=i.ssd_issuecode
left join ssd.ssd_magazines m on m.mag_id = s.mag_type and m.mag_id between 7 and 18);

-- Choose a single copy of duplicated reviews
update tmp_reviews set parent_id = id where id in (select min(id) from tmp_reviews group by review_text,review_comments,review_rating,reviewers);

update tmp_reviews set prefix_review_text = substr(review_text,1,100) where review_text is not null;

update tmp_reviews s1 inner join tmp_reviews s2
on s1.prefix_review_text = s2.prefix_review_text
and coalesce(s1.review_text,'') = coalesce(s2.review_text,'')
and coalesce(s1.review_comments,'') = coalesce(s2.review_comments,'')
and coalesce(s1.review_rating,'') = coalesce(s2.review_rating,'')
and coalesce(s1.reviewers,'') = coalesce(s2.reviewers,'')
set s1.parent_id = s2.parent_id
where s1.parent_id is null and s2.parent_id is not null;

-- Whenever the same review of the same game appears twice in SSD_Reviews, give each one a "score_group" name to distinguish between them
create table tmp_score_groups (
    entry_id int(11) not null,
    issue_id int(11) not null,
    page smallint(6) not null,
    overall_score varchar(255) not null,
    variant tinyint(4) not null,
    score_group varchar(100) not null,
    primary key(entry_id, issue_id, page, overall_score)
);

update tmp_reviews set variant=0, score_group='Classic Adventure' where entry_id = 6087 and issue_id=971 and page = 73 and review_text like 'Producer: M%';
update tmp_reviews set variant=1, score_group='Colossal Caves' where entry_id = 6087 and issue_id=971 and page = 73 and review_text like 'Producer: C%';

insert into tmp_score_groups (entry_id, issue_id, page, overall_score, variant, score_group) values
(176, 1007, 116, 94, 1, '128K'),   -- Amaurote
(176, 1007, 116, 92, 0, '48K'),
(4863, 1003, 22, 97, 1, '128K'),   -- Starglider
(4863, 1003, 22, 95, 0, '48K'),
(2054, 1001, 18, 92, 1, '128K'),   -- Glider Rider
(2054, 1001, 18, 80, 0, '48K'),
(4448, 94, 50, 85, 0, 'Charles Wood'),   -- Shark
(4448, 94, 50, 78, 1, 'Garth Sumpter'),
(5630, 94, 51, 35, 0, 'Andrew Buchan'),   -- War Machine
(5630, 94, 51, 61, 1, 'Garth Sumpter'),
(5218, 94, 50, 65, 0, 'Editor'),          -- Thanatos
(5218, 94, 50, 73, 1, 'Garth Sumpter'),
(5061, 995, 24, 86, 0, 'Pros'),   -- SuperCom
(5061, 995, 24, 21, 1, 'Cons');

update tmp_reviews t inner join ssd.ssd_reviews_scores s on t.id = s.review_id inner join tmp_score_groups x on t.entry_id = x.entry_id and t.issue_id = x.issue_id and t.page = x.page set t.variant = x.variant, t.score_group = x.score_group where s.review_header='Overall' and s.review_score = x.overall_score;

drop table tmp_score_groups;

-- Store review text in ZXDB
create table zxsr_reviews(
    id int(11) not null primary key,
    review_text longtext,
    review_comments longtext,
    review_rating varchar(2000),
    reviewers varchar(250)
);

insert into zxsr_reviews(id, review_text, review_comments, review_rating, reviewers) (select parent_id, review_text, review_comments, review_rating, reviewers from tmp_reviews group by parent_id, review_text, review_comments, review_rating, reviewers);

-- Modify existing ZXDB table magrefs
alter table magrefs add column score_group varchar(100) not null default '' after is_supplement;
alter table magrefs drop foreign key fk_magref_entry;
alter table magrefs drop foreign key fk_magref_issue;
alter table magrefs drop index uk_magref_entry;
alter table magrefs drop index uk_magref;
alter table magrefs add constraint uk_magref_entry unique(entry_id,issue_id,page,is_supplement,referencetype_id,score_group);
alter table magrefs add constraint uk_magref unique (issue_id,page,is_supplement,referencetype_id,entry_id,label_id,topic_id,score_group);
alter table magrefs add constraint fk_magref_entry foreign key (entry_id) references entries(id);
alter table magrefs add constraint fk_magref_issue foreign key (issue_id) references issues(id);
alter table magrefs add column review_id int(11) after score_group;
alter table magrefs add constraint fk_magref_review foreign key (review_id) references zxsr_reviews(id);
alter table magrefs add column award_id tinyint(4) after review_id;
alter table magrefs add constraint fk_magref_award foreign key (award_id) references zxsr_awards(id);

-- Add a magazine reference in magrefs if it's not already there
insert into magrefs(referencetype_id, entry_id, issue_id, page, is_supplement) (select 10, entry_id, issue_id, page, is_supplement from tmp_reviews where id not in (select t.id from tmp_reviews t inner join magrefs r on t.entry_id = r.entry_id and t.issue_id = r.issue_id and t.page = r.page and t.is_supplement = r.is_supplement and r.referencetype_id = 10) group by entry_id, issue_id, page, is_supplement);

-- Store review information in magrefs
update tmp_reviews t inner join magrefs r on t.entry_id = r.entry_id and t.issue_id = r.issue_id and t.page = r.page and t.is_supplement = r.is_supplement and r.referencetype_id = 10 set r.score_group = t.score_group, r.review_id = t.parent_id, r.award_id = t.award_id where t.variant = 0;

insert into magrefs(referencetype_id, entry_id, issue_id, page, is_supplement, score_group, review_id, award_id) (select 10, entry_id, issue_id, page, is_supplement, score_group, parent_id, award_id from tmp_reviews where variant=1);

update tmp_reviews t inner join magrefs r on t.entry_id = r.entry_id
and t.issue_id = r.issue_id
and t.page = r.page
and t.is_supplement = r.is_supplement
and t.score_group = r.score_group
and r.referencetype_id = 10
set t.magref_id = r.id;

-- Store review "mag section" in ZXDB
insert into magreffeats (magref_id, feature_id) (select t.magref_id, f.id from tmp_reviews t left join features f on f.name = t.mag_section and f.id between 100 and 800 left join magreffeats z on z.magref_id = t.magref_id and z.feature_id = f.id where t.mag_section is not null and z.magref_id is null group by t.magref_id, f.id);

-- Store review scores in ZXDB
create table zxsr_scores(
    magref_id int(11) not null,
    score_seq tinyint(4) not null,
    category varchar(100) not null,
    is_overall tinyint(1) not null,
    score varchar(100),
    comments varchar(1000),
    constraint fk_zxsr_score_magref foreign key (magref_id) references magrefs(id),
    constraint bk_zxsr_score_overall check (is_overall in (0,1)),
    primary key(magref_id,score_seq)
);

insert into zxsr_scores(magref_id, score_seq, category, is_overall, score, comments) (select t.magref_id, s.header_order, s.review_header, 0, nullif(concat(coalesce(trim(s.review_score),''),coalesce(trim(s.score_suffix),'')),''),nullif(s.score_text,'') from ssd.ssd_reviews_scores s inner join tmp_reviews t on s.review_id = t.id);

-- Add a reference to the compilation content's review in ZXDB if it's not already there
insert into magrefs(referencetype_id, entry_id, issue_id, page, is_supplement)
(select 10, g.WOSID, t.issue_id, t.page, t.is_supplement from ssd.ssd_reviews_scores_compilations c
inner join ssd.ssd_game g on g.ID = c.game_id
inner join tmp_reviews t on c.review_id = t.id
where c.score_id not in (
select c.score_id from ssd.ssd_reviews_scores_compilations c
inner join ssd.ssd_game g on g.ID = c.game_id
inner join tmp_reviews t on c.review_id = t.id
inner join magrefs r on g.WOSID = r.entry_id
and t.issue_id = r.issue_id
and t.page = r.page
and t.is_supplement = r.is_supplement
and r.referencetype_id = 10)
group by g.WOSID, t.issue_id, t.page, t.is_supplement);

-- Store compilation content's review information in magrefs
update ssd.ssd_reviews_scores_compilations c
inner join ssd.ssd_game g on g.ID = c.game_id
inner join tmp_reviews t on c.review_id = t.id
inner join magrefs r on g.WOSID = r.entry_id
and t.issue_id = r.issue_id
and t.page = r.page
and t.is_supplement = r.is_supplement
and r.referencetype_id = 10
and r.score_group = ''
set r.review_id = t.parent_id;

-- Store compilation content's review scores in ZXDB
insert into zxsr_scores(magref_id, score_seq, category, is_overall, score) (select r.id, c.header_order, c.review_header, 0, nullif(concat(coalesce(trim(c.review_score),''),coalesce(trim(c.score_suffix),'')),'')
from ssd.ssd_reviews_scores_compilations c
inner join ssd.ssd_game g on g.ID = c.game_id
inner join tmp_reviews t on c.review_id = t.id
inner join magrefs r on g.WOSID = r.entry_id
and t.issue_id = r.issue_id
and t.page = r.page
and t.is_supplement = r.is_supplement
and r.referencetype_id = 10 and
r.score_group = '');

-- Store review picture description in ZXDB
create table zxsr_captions(
    id int(11) not null,
    magref_id int(11) not null,
    caption_seq smallint(6) not null,
    text varchar(10000) not null,
    is_banner tinyint(1) not null,
    constraint fk_zxsr_caption_magref foreign key (magref_id) references magrefs(id),
    constraint bk_zxsr_caption_banner check (is_banner in (0,1))
);

insert into zxsr_captions(id, magref_id, caption_seq, text, is_banner) (select s.id,t.magref_id, 0, s.TheText, s.IsBanner from ssd.ssd_reviews_picturetext s inner join tmp_reviews t on s.ReviewId = t.id);

-- Calculate review picture description sequences
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);
update zxsr_captions set caption_seq=(select max(caption_seq)+1 from zxsr_captions) where id in (select min(id) from zxsr_captions where caption_seq=0 group by magref_id);

alter table zxsr_captions add primary key(magref_id,caption_seq,is_banner);
alter table zxsr_captions drop column id;

drop table if exists tmp_reviews;
drop table if exists tmp_issues;
drop table if exists tmp_magazines;

update zxsr_scores s1 left join zxsr_scores s2 on s1.magref_id = s2.magref_id and s2.score_seq = s1.score_seq+1 set s1.is_overall = 1 where s2.magref_id is null and (s1.score_seq = 1 or s1.category = 'Ace Rating' or (s1.category like 'Overall%' and s1.category not like 'Overall (%'));

insert into zxsr_scores(magref_id, score_seq, category, is_overall, score) (select id, 1, 'Score', 1, score from magrefs where score is not null and id not in (select magref_id from zxsr_scores));

update magrefs r inner join zxsr_scores s on s.magref_id = r.id and s.is_overall = 1 set r.score = null where r.score is not null and (r.score = coalesce(s.score,'') or concat(r.score,'/10') = coalesce(s.score,''));

update zxsr_scores set category = 'Stars', score = replace(score,' stars','') where score like '% stars';

update magrefs set score = null where score = 'Not Rated';

-- END
