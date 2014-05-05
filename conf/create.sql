DROP TABLE IF EXISTS QUIZ_USER;
CREATE TABLE QUIZ_USER (
	ID SERIAL PRIMARY KEY,
	NAME VARCHAR(100) NOT NULL,
	TWITTER_ID BIGINT NULL,
	TWITTER_SCREEN_NAME VARCHAR(20) NULL,
	FACEBOOK_ID BIGINT NULL,
	FACEBOOK_SCREEN_NAME VARCHAR(20) NULL,
	IMAGE_URL TEXT NOT NULL,
	LAST_LOGIN TIMESTAMP NULL,
	CREATED TIMESTAMP NOT NULL,
	UPDATED TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS QUIZ_ROOM;
CREATE TABLE QUIZ_ROOM (
	ID SERIAL PRIMARY KEY,
	NAME VARCHAR(100) NOT NULL,
	TAGS VARCHAR(100) NULL,
	HASHTAG VARCHAR(20) NULL,
	USER_QUIZ BOOLEAN NOT NULL DEFAULT FALSE,
	DESCRIPTION TEXT NULL,
	OWNER INT NOT NULL,
	ADMIN_USERS TEXT NULL,
	CREATED TIMESTAMP NOT NULL,
	UPDATED TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS QUIZ_EVENT;
CREATE TABLE QUIZ_EVENT (
	ID SERIAL PRIMARY KEY,
	ROOM_ID INT NOT NULL,
	TITLE VARCHAR(100) NULL,
	STATUS SMALLINT NOT NULL DEFAULT 0,
	ADMIN INT NULL,
	EXEC_DATE TIMESTAMP NULL,
	END_DATE TIMESTAMP NULL,
	CAPACITY INT NOT NULL,
	ANSWER_TIME INT NOT NULL DEFAULT 10,
	PASSCODE VARCHAR(100) NULL,
	DESCRIPTION TEXT NULL,
	CREATED TIMESTAMP NOT NULL,
	UPDATED TIMESTAMP NOT NULL
);

#alter table QUIZ_EVENT ADD COLUMN ANSWER_TIME INT NOT NULL DEFAULT 10;

DROP TABLE IF EXISTS QUIZ_QUESTION;
CREATE TABLE QUIZ_QUESTION (
	ID SERIAL PRIMARY KEY,
	ROOM_ID INT NOT NULL,
	CREATED_BY INT NOT NULL,
	QUESTION TEXT NOT NULL,
	ANSWERS TEXT NOT NULL,
	ANSWER_TYPE SMALLINT NOT NULL,
	TAGS VARCHAR(100) NULL,
	DESCRIPTION TEXT NULL,
	RELATED_URL VARCHAR(256) NULL,
	PUBLISH_COUNT INT NOT NULL DEFAULT 0,
	CORRECT_COUNT INT NOT NULL DEFAULT 0,
	WRONG_COUNT INT NOT NULL DEFAULT 0,
	CREATED TIMESTAMP NOT NULL,
	UPDATED TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS QUIZ_USER_EVENT;
CREATE TABLE QUIZ_USER_EVENT (
	ID SERIAL PRIMARY KEY,
	USER_ID INT NOT NULL,
	EVENT_ID INT NOT NULL,
	ROOM_ID INT NOT NULL,
	CORRECT_COUNT INT NOT NULL DEFAULT 0,
	WRONG_COUNT INT NOT NULL DEFAULT 0,
	TIME BIGINT NOT NULL DEFAULT 0,
	POINT INT NOT NULL DEFAULT 0,
	CREATED TIMESTAMP NOT NULL,
	UPDATED TIMESTAMP NOT NULL
);

DROP TABLE IF EXISTS QUIZ_PUBLISH;
CREATE TABLE QUIZ_PUBLISH (
	ID SERIAL PRIMARY KEY,
	EVENT_ID INT NOT NULL,
	QUESTION_ID INT NOT NULL,
	CORRECT_ANSWER INT NOT NULL,
	ANSWERS_INDEX VARCHAR(10) NOT NULL,
	INCLUDE_RANKING BOOLEAN NOT NULL,
	ANSWER_TIME INT NOT NULL DEFAULT 10,
	CREATED TIMESTAMP NOT NULL,
	UPDATED TIMESTAMP NOT NULL
);

#alter table QUIZ_PUBLISH ADD COLUMN ANSWER_TIME INT NOT NULL DEFAULT 10;

DROP TABLE IF EXISTS QUIZ_USER_ANSWER;
CREATE TABLE QUIZ_USER_ANSWER (
	ID SERIAL PRIMARY KEY,
	USER_ID INT NOT NULL,
	PUBLISH_ID INT NOT NULL,
	EVENT_ID INT NOT NULL,
	USER_EVENT_ID INT NOT NULL,
	ANSWER INT NOT NULL,
	STATUS SMALLINT NOT NULL,
	TIME INT NOT NULL,
	CREATED TIMESTAMP NOT NULL,
	UPDATED TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX UK_QUIZ_PUBLISH ON QUIZ_PUBLISH (EVENT_ID, QUESTION_ID);
CREATE UNIQUE INDEX UK_QUIZ_USER_EVENT ON QUIZ_USER_EVENT (USER_ID, EVENT_ID);
CREATE UNIQUE INDEX UK_QUIZ_USER_ANSWER ON QUIZ_USER_ANSWER (USER_ID, PUBLISH_ID);

CREATE INDEX IDX_QUIZ_EVENT_ROOM ON QUIZ_EVENT (ROOM_ID);
CREATE INDEX IDX_QUIZ_QUESTION_ROOM ON QUIZ_QUESTION (ROOM_ID);
--CREATE INDEX IDX_QUIZ_USER_EVENT_USER ON QUIZ_USER_EVENT (USER_ID);//Because unique index exists
CREATE INDEX IDX_QUIZ_USER_EVENT_EVENT ON QUIZ_USER_EVENT (EVENT_ID);
--CREATE INDEX IDX_QUIZ_PUBLISH_EVENT ON QUIZ_PUBLISH (EVENT_ID);//Because unique index exists
CREATE INDEX IDX_QUIZ_PUBLISH_QUESTION ON QUIZ_PUBLISH (QUESTION_ID);
--CREATE INDEX IDX_QUIZ_USER_ANSWER_USER ON QUIZ_USER_ANSWER (USER_ID);//Because unique index exists
CREATE INDEX IDX_QUIZ_USER_ANSWER_PUBLISH ON QUIZ_USER_ANSWER (PUBLISH_ID);
CREATE INDEX IDX_QUIZ_USER_ANSWER_USER ON QUIZ_USER_ANSWER (USER_ID);
CREATE INDEX IDX_QUIZ_USER_ANSWER_USER_EVENT ON QUIZ_USER_ANSWER (USER_EVENT_ID);
CREATE INDEX IDX_QUIZ_USER_ANSWER_EVENT ON QUIZ_USER_ANSWER (EVENT_ID);

DROP VIEW IF EXISTS QUIZ_RANKING;
CREATE VIEW QUIZ_RANKING (
	EVENT_ID,
	USER_ID,
	USERNAME,
	IMAGE_URL,
	CORRECT_COUNT,
	WRONG_COUNT,
	TIME
) AS 
SELECT E.EVENT_ID,
       E.USER_ID,
       U.NAME,
       U.IMAGE_URL,
       SUM(CASE
       	 WHEN A.STATUS IS NULL THEN 0
         WHEN A.STATUS = 1 THEN 1
         WHEN A.STATUS = 2 THEN 0
         WHEN P.CORRECT_ANSWER = A.ANSWER THEN 1
         ELSE 0 END
       ),
       SUM(CASE
       	 WHEN A.STATUS IS NULL THEN 0
         WHEN A.STATUS = 1 THEN 0
         WHEN A.STATUS = 2 THEN 1
         WHEN P.CORRECT_ANSWER = 0 THEN 0
         WHEN P.CORRECT_ANSWER = A.ANSWER THEN 0
         ELSE 1 END
       ),
       SUM(CASE
       	 WHEN A.STATUS IS NULL THEN 0
         WHEN A.STATUS = 1 THEN A.TIME
         WHEN A.STATUS = 2 THEN 0
         WHEN P.CORRECT_ANSWER = A.ANSWER THEN A.TIME
         ELSE 0 END
       )
  FROM QUIZ_USER_EVENT E
 INNER JOIN QUIZ_USER U ON (E.USER_ID = U.ID)
  LEFT JOIN QUIZ_USER_ANSWER A ON (E.ID = A.USER_EVENT_ID)
  LEFT JOIN QUIZ_PUBLISH P ON (A.PUBLISH_ID = P.ID AND P.INCLUDE_RANKING = TRUE)
 GROUP BY E.EVENT_ID, E.USER_ID, U.NAME, U.IMAGE_URL;

DROP VIEW IF EXISTS QUIZ_ANSWER_COUNT;
CREATE VIEW QUIZ_ANSWER_COUNT (
	EVENT_ID,
	PUBLISH_ID,
	QUESTION_ID,
	ANSWER1,
	ANSWER2,
	ANSWER3,
	ANSWER4,
	ANSWER5,
	CORRECT_COUNT,
	WRONG_COUNT
) AS 
SELECT P.EVENT_ID,
       A.PUBLISH_ID,
       P.QUESTION_ID,
       SUM(CASE WHEN A.ANSWER = 1 THEN 1 ELSE 0 END),
       SUM(CASE WHEN A.ANSWER = 2 THEN 1 ELSE 0 END),
       SUM(CASE WHEN A.ANSWER = 3 THEN 1 ELSE 0 END),
       SUM(CASE WHEN A.ANSWER = 4 THEN 1 ELSE 0 END),
       SUM(CASE WHEN A.ANSWER = 5 THEN 1 ELSE 0 END),
       SUM(CASE
         WHEN A.STATUS = 1 THEN 1
         WHEN A.STATUS = 2 THEN 0
         WHEN P.CORRECT_ANSWER = A.ANSWER THEN 1
         ELSE 0 END
       ),
       SUM(CASE
         WHEN A.STATUS = 1 THEN 0
         WHEN A.STATUS = 2 THEN 1
         WHEN P.CORRECT_ANSWER = 0 THEN 0
         WHEN P.CORRECT_ANSWER = A.ANSWER THEN 0
         ELSE 1 END
       )
  FROM QUIZ_USER_ANSWER A
 INNER JOIN QUIZ_PUBLISH P ON (A.PUBLISH_ID = P.ID)
 GROUP BY P.EVENT_ID, A.PUBLISH_ID, P.QUESTION_ID;

DROP VIEW IF EXISTS QUIZ_EVENT_WINNER;
CREATE VIEW QUIZ_EVENT_WINNER (
	ROOM_ID,
	EVENT_ID,
	EXEC_DATE,
	TITLE,
	USER_ID,
	USERNAME,
	IMAGE_URL,
	CORRECT_COUNT,
	WRONG_COUNT,
	TIME,
	MEMBER
) AS 
SELECT 
  A.ROOM_ID, 
  A.ID,
  A.EXEC_DATE,
  A.TITLE,
  B.USER_ID,
  C.NAME,
  C.IMAGE_URL,
  B.CORRECT_COUNT,
  B.WRONG_COUNT,
  B.TIME,
  D.MEMBER
FROM QUIZ_EVENT A
LEFT JOIN QUIZ_USER_EVENT B ON (A.ID = B.EVENT_ID AND B.POINT = 10)
LEFT JOIN QUIZ_USER C ON (B.USER_ID = C.ID)
INNER JOIN (SELECT EVENT_ID, COUNT(*) AS MEMBER
             FROM QUIZ_USER_EVENT
         GROUP BY EVENT_ID
          ) D ON (A.ID = D.EVENT_ID);

DROP VIEW IF EXISTS QUIZ_TOTAL_RANKING;
CREATE VIEW QUIZ_TOTAL_RANKING (
	ROOM_ID,
	USER_ID,
	USERNAME,
	IMAGE_URL,
	POINT,
	CORRECT_COUNT,
	WRONG_COUNT,
	TIME
) AS
SELECT
  A.ROOM_ID,
  A.USER_ID,
  B.NAME,
  B.IMAGE_URL,
  SUM(A.POINT),
  SUM(A.CORRECT_COUNT),
  SUM(A.WRONG_COUNT),
  SUM(TIME)
FROM QUIZ_USER_EVENT A
INNER JOIN QUIZ_USER B ON (A.USER_ID = B.ID)
GROUP BY A.ROOM_ID, A.USER_ID, B.NAME, B.IMAGE_URL;

-- DELETE
DELETE FROM QUIZ_USER;
DELETE FROM QUIZ_ROOM;
DELETE FROM QUIZ_QUESTION;
DELETE FROM QUIZ_EVENT;
DELETE FROM QUIZ_PUBLISH;
DELETE FROM QUIZ_USER_EVENT;
DELETE FROM QUIZ_USER_ANSWER;
