package models

import play.api.libs.json._
import play.api.libs.iteratee.Iteratee
import play.api.libs.iteratee.Enumerator
import scala.concurrent.Future
import org.joda.time.DateTime
import scalikejdbc._
import scalikejdbc.SQLInterpolation._

import models.entities.QuizRoom
import models.entities.QuizEvent
import models.sqlviews.QuizEventWinner
import models.sqlviews.QuizRanking
import models.sqlviews.QuizTotalRanking
import models.sqlviews.QuizAnswerCount

import flect.websocket.Command
import flect.websocket.CommandHandler
import flect.websocket.CommandResponse
import flect.redis.Room
import flect.redis.RedisService

class RoomManager(redis: RedisService) extends flect.redis.RoomManager[RedisRoom](redis) {

  private val DEFAULT_RANKING_LIMIT = 10;

  override protected def terminate() = {
    super.terminate()
    redis.close
  }
  
  private val (qr, qe) = (QuizRoom.qr, QuizEvent.qe)
  implicit val autoSession = AutoSession

  override protected def createRoom(name: String) = {
    val id = name.substring(5).toInt
    val info = getRoomInfo(id, false).get
    new RedisRoom(info, redis)
  }

  def getRoom(id: Int): RedisRoom = getRoom("room." + id)
  def join(id: Int): Future[(Iteratee[String,_], Enumerator[String])] = join("room." + id)

  def getRoomInfo(id: Int, includeCurrentEvent: Boolean): Option[RoomInfo] = {
    val room = QuizRoom.find(id).map(RoomInfo.create(_))
    if (includeCurrentEvent) {
      room.map(_.copy(
        event = EventManager(id).getCurrentEvent
      ))
    } else {
      room
    }
  }

  def create(room: RoomInfo): RoomInfo = {
    val now = new DateTime()
    val entity = QuizRoom.create(
      name=room.name,
      tags=room.tags,
      hashtag=room.hashtag,
      userQuiz=room.userQuiz,
      description=room.description,
      owner=room.owner,
      adminUsers=room.adminUsers,
      created=now,
      updated=now
    )
    RoomInfo.create(entity)
  }

  def update(room: RoomInfo): Boolean = {
    QuizRoom.find(room.id).map { entity =>
      entity.copy(
        name=room.name,
        tags=room.tags,
        hashtag=room.hashtag,
        userQuiz=room.userQuiz,
        description=room.description,
        adminUsers=room.adminUsers,
        updated= new DateTime()
      ).save();
      true;
    }.getOrElse(false)
  }

  def list(offset: Int, limit: Int, userId: Option[Int]): List[RoomInfo] = {
    val where = userId.map(n => sqls""" where exists(
      select * from quiz_user_event que
              where que.room_id = qr.id
                and que.user_id = ${n}) or qr.owner = ${n}"""
    ).getOrElse(sqls"")
    withSQL { 
      select
        .from(QuizRoom as qr)
        .leftJoin(QuizEvent as qe).on(sqls"qr.id = qe.room_id and qe.status in (0, 1)")
        .append(where)
        .orderBy(sqls"COALESCE(qe.exec_date, qr.updated)").desc
        .limit(limit).offset(offset)
    }.map { rs =>
      val room = RoomInfo.create(QuizRoom(qr.resultName)(rs))
      val event = rs.intOpt(qe.resultName.roomId).map(_ => EventInfo.create(QuizEvent(qe.resultName)(rs)))
      event.map(room.withEvent(_)).getOrElse(room)
    }.list.apply
  }

  def listUserEntriedRooms(userId: Int, offset: Int, limit: Int): List[UserEntriedRoom] = {
    sql"""
      select B.id, B.name as room_name, B.owner, B.updated, 
             C.name as owner_name, C.image_url, A.user_id, 
             SUM(A.point) as point, SUM(A.correct_count) as correct_count
        from quiz_user_event A
  inner join quiz_room B on (A.room_id = B.id)
  inner join quiz_user C on (B.owner = C.id)
       where A.user_id = ${userId}
    group by B.id, B.name, B.owner, B.updated, C.name, C.image_url, A.user_id
    order by B.updated desc
    limit ${limit} offset ${offset}
    """.map { rs =>
      UserEntriedRoom(
        roomId=rs.int("id"),
        roomName=rs.string("room_name"),
        owner=rs.int("owner"),
        ownerName=rs.string("owner_name"),
        ownerImage=rs.string("image_url"),
        userId=rs.int("user_id"),
        point=rs.int("point"),
        correctCount=rs.int("correct_count")
      )
    }.list.apply
  }

  def listOwnedRooms(userId: Int, offset: Int, limit: Int): List[OwnedRoom] = {
    sql"""
      select A.id, A.name as room_name, A.owner, A.updated, 
             B.name as owner_name, B.image_url, 
             SUM(C.count) as event_count, SUM(D.count) as question_count
        from quiz_room A
  inner join quiz_user B on (A.owner = B.id)
   left join (select room_id, count(*) as count 
                from quiz_event
            group by room_id) C on (A.id = C.room_id)
   left join (select room_id, count(*) as count 
                from quiz_question
            group by room_id) D on (A.id = D.room_id)
       where A.owner = ${userId}
    group by A.id, A.name, A.owner, A.updated, B.name, B.image_url
    order by A.updated desc
    limit ${limit} offset ${offset}
    """.map { rs =>
      OwnedRoom(
        roomId=rs.int("id"),
        roomName=rs.string("room_name"),
        owner=rs.int("owner"),
        ownerName=rs.string("owner_name"),
        ownerImage=rs.string("image_url"),
        eventCount=rs.intOpt("event_count").getOrElse(0),
        questionCount=rs.intOpt("question_count").getOrElse(0)
      )
    }.list.apply
  }

  def getMemberCount(eventId: Int): Int = {
    sql"select count(*) from quiz_user_event where event_id = ${eventId}"
      .map(_.int(1)).single.apply.getOrElse(0)
  }

  def getPublishedQuestions(eventId: Int): List[Int] = {
    sql"select question_id from quiz_publish where event_id = ${eventId}"
      .map(_.int(1)).list.apply
  }

  def getEventRanking(eventId: Int, limit: Int, offset: Int): List[QuizRanking] = {
    QuizRanking.findByEventId(eventId, limit, offset)
  }

  def getEventWinners(roomId: Int): List[QuizEventWinner] = {
    QuizEventWinner.findByRoomId(roomId)
  }

  def getTotalRanking(roomId: Int, limit: Int): List[QuizTotalRanking] = {
    QuizTotalRanking.findByRoomId(roomId, limit)
  }

  def getUserTotalRanking(roomId: Int, userId: Int): Option[Int] = {
    val numbers = sql"""
      select sum(point), sum(correct_count), sum(time) from quiz_user_event
       where room_id = ${roomId} and user_id = ${userId}
    """.map {rs =>
      (rs.int(1), rs.int(2), rs.int(3))
    }.single.apply
    numbers match {
      case Some((point, correctCount, time)) if correctCount > 0 =>
        val cnt = sql"""
          select count(*) from quiz_total_ranking
           where (point > ${point})
              or (point = ${point} and correct_count > ${correctCount})
              or (point = ${point} and correct_count = ${correctCount} and time < ${time})
        """.map(_.int(1)).single.apply.get
        Some(cnt + 1)
      case _ => None
    }
  }

  def getEventQuestions(eventId: Int, userId: Int): List[UserQuestionInfo] = {
    sql"""
      select A.question_id, B.question, 
             case when C.user_id is null then false
                  else true
             end,
             case when C.status is null then false
                  when C.status = 1 then true
                  when C.status = 2 then false
                  when A.correct_answer = 0 then false
                  when A.correct_answer = C.answer then true
                  else false
             end
        from quiz_publish A
  inner join quiz_question B on (A.question_id = B.id)
   left join quiz_user_answer C on (A.id = C.publish_id and C.user_id = ${userId})
       where A.event_id = ${eventId}
    order by A.id
    """.map { rs =>
      UserQuestionInfo(
        questionId=rs.int(1),
        question=rs.string(2),
        answered=rs.boolean(3),
        correct=rs.boolean(4)
      )
    }.list.apply
  }

  def getUserEvent(roomId: Int, userId: Int): List[UserEventInfo] = {
    sql"""
      select A.id, A.user_id, A.event_id, A.room_id, B.title, B.exec_date,
             A.correct_count, A.wrong_count, A.time, A.point
        from quiz_user_event A
  inner join quiz_event B on (A.event_id = B.id)
       where A.room_id = ${roomId} and A.user_id = ${userId}
    order by A.event_id desc
    """.map { rs =>
      UserEventInfo(
        id=rs.int("id"),
        userId=rs.int("user_id"),
        eventId=rs.int("event_id"),
        roomId=rs.int("room_id"),
        title=rs.stringOpt("title"),
        execDate=rs.timestampOpt("exec_date").map(_.toDateTime),
        correctCount=rs.int("correct_count"),
        wrongCount=rs.int("wrong_count"),
        time=rs.int("time"),
        point=rs.int("point")
      )
    }.list.apply
  }

  val createCommand = CommandHandler { command =>
    val room = create(RoomInfo.fromJson(command.data))
    command.json(room.toJson)
  }

  val updateCommand = CommandHandler { command =>
    update(RoomInfo.fromJson(command.data))
    command.text("OK")
  }

  val getCommand = CommandHandler { command =>
    val id = command.data.as[Int]
    val room = getRoomInfo(id, false)
    val data = room.map(_.toJson).getOrElse(JsNull)
    command.json(data)
  }

  val listCommand = CommandHandler { command =>
    val limit = (command.data \ "limit").as[Int]
    val offset = (command.data \ "offset").as[Int]
    val userId = (command.data \ "userId").asOpt[Int]
    val data = list(offset, limit, userId).map(_.toJson)
    command.json(JsArray(data))
  }

  val entriedRoomsCommand = CommandHandler { command =>
    val userId = (command.data \ "userId").as[Int]
    val limit = (command.data \ "limit").as[Int]
    val offset = (command.data \ "offset").as[Int]
    val data = listUserEntriedRooms(userId, offset, limit).map(_.toJson)
    command.json(JsArray(data))
  }

  val ownedRoomsCommand = CommandHandler { command =>
    val userId = (command.data \ "userId").as[Int]
    val limit = (command.data \ "limit").as[Int]
    val offset = (command.data \ "offset").as[Int]
    val data = listOwnedRooms(userId, offset, limit).map(_.toJson)
    command.json(JsArray(data))
  }

  val eventRankingCommand = CommandHandler { command =>
    val eventId = (command.data \ "eventId").as[Int]
    val limit = (command.data \ "limit").asOpt[Int].getOrElse(DEFAULT_RANKING_LIMIT)
    val offset = (command.data \ "offset").asOpt[Int].getOrElse(0)
    val data = JsArray(getEventRanking(eventId, limit, offset).map(_.toJson))
    command.json(data)
  }

  val eventWinnersCommand = CommandHandler { command =>
    val roomId = (command.data \ "roomId").as[Int]
    val data = JsArray(getEventWinners(roomId).map(_.toJson))
    command.json(data)
  }

  val totalRankingCommand = CommandHandler { command =>
    val roomId = (command.data \ "roomId").as[Int]
    val limit = (command.data \ "limit").asOpt[Int].getOrElse(DEFAULT_RANKING_LIMIT)
    val data = JsArray(getTotalRanking(roomId, limit).map(_.toJson))
    command.json(data)
  }

  val userTotalRankingCommand = CommandHandler { command =>
    val roomId = (command.data \ "roomId").as[Int]
    val userId = (command.data \ "userId").as[Int]
    val data = getUserTotalRanking(roomId, userId).map(JsNumber(_)).getOrElse(JsNull)
    command.json(data)
  }

  val userEventCommand = CommandHandler { command =>
    val roomId = (command.data \ "roomId").as[Int]
    val userId = (command.data \ "userId").as[Int]
    val data = JsArray(getUserEvent(roomId, userId).map(_.toJson))
    command.json(data)
  }

  val memberCountCommand = CommandHandler { command =>
    val eventId = command.data.as[Int]
    val data = JsNumber(getMemberCount(eventId))
    command.json(data)
  }

  val publishedQuestionsCommand = CommandHandler { command =>
    val eventId = command.data.as[Int]
    val data = JsArray(getPublishedQuestions(eventId).map(JsNumber(_)))
    command.json(data)
  }

  val eventQuestionsCommand = CommandHandler { command =>
    val eventId = (command.data \ "eventId").as[Int]
    val userId = (command.data \ "userId").as[Int]
    val data = JsArray(getEventQuestions(eventId, userId).map(_.toJson))
    command.json(data)
  }
}

object RoomManager extends RoomManager(MyRedisService)
