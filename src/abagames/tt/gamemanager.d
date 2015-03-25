/*
 * $Id: gamemanager.d,v 1.6 2005/01/09 03:49:59 kenta Exp $
 *
 * Copyright 2004 Kenta Cho. Some rights reserved.
 */
module abagames.tt.gamemanager;

private import std.math;
private import std.typecons;
private import derelict.sdl2.sdl;
private import bml = bulletml.bulletml;
private import gl3n.linalg;
private import abagames.util.rand;
private import abagames.util.support.gl;
private import abagames.util.bulletml.bullet;
private import abagames.util.sdl.gamemanager;
private import abagames.util.sdl.texture;
private import abagames.util.sdl.pad;
private import abagames.util.sdl.recordablepad;
private import abagames.tt.prefmanager;
private import abagames.tt.screen;
private import abagames.tt.ship;
private import abagames.tt.tunnel;
private import abagames.tt.bulletactor;
private import abagames.tt.bulletactorpool;
private import abagames.tt.barrage;
private import abagames.tt.enemy;
private import abagames.tt.stagemanager;
private import abagames.tt.shape;
private import abagames.tt.particle;
private import abagames.tt.letter;
private import abagames.tt.shot;
private import abagames.tt.floatletter;
private import abagames.tt.title;
private import abagames.tt.soundmanager;
private import abagames.tt.replay;

/**
 * Manage the game state and actor pools.
 */
public class GameManager: abagames.util.sdl.gamemanager.GameManager {
 private:
  Pad pad;
  PrefManager prefManager;
  Screen screen;
  Tunnel tunnel;
  Ship ship;
  ShotPool shots;
  BulletActorPool bullets;
  EnemyPool enemies;
  ParticlePool particles;
  FloatLetterPool floatLetters;
  StageManager stageManager;
  TitleManager titleManager;
  EnemyPool passedEnemies;
  Rand rand;
  float interval;
  GameState state;
  TitleState titleState;
  InGameState inGameState;
  mat4 windowmat;
  bool escPressed;

  public override void init(mat4 windowmat) {
    BarrageManager.load();
    Letter.init();
    Shot.init();
    pad = cast(Pad) input;
    prefManager = cast(PrefManager) abstPrefManager;
    screen = cast(Screen) abstScreen;
    interval = mainLoop.INTERVAL_BASE;
    tunnel = new Tunnel;
    ship = new Ship(pad, tunnel);
    Object[] fargs;
    fargs ~= tunnel;
    floatLetters = new FloatLetterPool(16, fargs);
    pad = cast(Pad) input;
    Object[] bargs;
    bargs ~= tunnel;
    bargs ~= ship;
    bullets = new BulletActorPool(512, bargs);
    Object[] pargs;
    pargs ~= tunnel;
    pargs ~= ship;
    particles = new ParticlePool(1024, pargs);
    Object[] eargs;
    eargs ~= tunnel;
    eargs ~= bullets;
    eargs ~= ship;
    eargs ~= particles;
    enemies = new EnemyPool(64, eargs);
    passedEnemies = new EnemyPool(64, eargs);
    enemies.setPassedEnemies(passedEnemies);
    Object[] sargs;
    sargs ~= tunnel;
    sargs ~= enemies;
    sargs ~= bullets;
    sargs ~= floatLetters;
    sargs ~= particles;
    sargs ~= ship;
    shots = new ShotPool(64, sargs);
    ship.setParticles(particles);
    ship.setShots(shots);
    stageManager = new StageManager(tunnel, enemies, ship);
    SoundManager.loadSounds();
    titleManager = new TitleManager(prefManager, pad, ship, this);
    rand = new Rand;

    inGameState = new InGameState(tunnel, ship, shots, bullets, enemies,
                                  particles, floatLetters, stageManager,
                                  pad, prefManager, this);
    titleState = new TitleState(tunnel, ship, shots, bullets, enemies,
                                particles, floatLetters, stageManager,
                                pad, titleManager, passedEnemies, inGameState);
    inGameState.seed = rand.nextInt32();
    ship.setGameState(inGameState);

    this.windowmat = windowmat;
  }

  public override void start() {
    loadLastReplay();
    startTitle();
  }

  public void startTitle(bool fromGameover = false) {
    if (fromGameover)
      saveLastReplay();
    titleState.setReplayData(inGameState.replayData);
    state = titleState;
    startState();
  }

  public void startInGame() {
    state = inGameState;
    startState();
  }

  private void startState() {
    state.grade = prefManager.prefData.selectedGrade;
    state.level = prefManager.prefData.selectedLevel;
    state.seed = rand.nextInt32();
    state.start();
  }

  public override void close() {
    stageManager.close();
    titleState.close();
    ship.close();
    Shot.close();
    Letter.close();
  }

  public void saveErrorReplay() {
    if (state == inGameState)
      inGameState.saveReplay("error.rpl");
  }

  private void saveLastReplay() {
    try {
      inGameState.saveReplay("last.rpl");
    } catch (Throwable o) {}
  }

  private void loadLastReplay() {
    try {
      inGameState.loadReplay("last.rpl");
    } catch (Throwable o) {
      inGameState.resetReplay();
    }
  }

  public override void move() {
    if (pad.keys[SDLK_ESCAPE] == SDL_PRESSED) {
      if (!escPressed) {
        escPressed = true;
        if (state == inGameState) {
          startTitle();
        } else {
          mainLoop.breakLoop();
        }
        return;
      }
    } else {
      escPressed = false;
    }
    state.move();
  }

  public override void draw() {
    SDL_Event e = mainLoop.event;
    if (e.type == SDL_WINDOWEVENT_RESIZED) {
      SDL_WindowEvent we = e.window;
      Sint32 w = we.data1;
      Sint32 h = we.data2;
      if (w > 150 && h > 100)
        windowmat = screen.resized(w, h);
    }
    if (screen.startRenderToLuminousScreen()) {
      glPushMatrix();
      Tuple!(mat4, mat4) mats = ship.setEyepos();
      state.drawLuminous(windowmat * mats[0] * mats[1]);
      glPopMatrix();
      screen.endRenderToLuminousScreen();
    }
    screen.clear();
    glPushMatrix();
    Tuple!(mat4, mat4) mats = ship.setEyepos();
    mat4 view = windowmat * mats[0];
    state.draw(view * mats[1]);
    glPopMatrix();
    screen.drawLuminous(view);
    mat4 orthoView = screen.viewOrthoFixed();
    state.drawFront(orthoView);
    screen.viewPerspective();
  }
}

/**
 * Manage the game state.
 * (e.g. title, in game, gameover, pause, ...)
 */
public class GameState {
 protected:
  Tunnel tunnel;
  Ship ship;
  ShotPool shots;
  BulletActorPool bullets;
  EnemyPool enemies;
  ParticlePool particles;
  FloatLetterPool floatLetters;
  StageManager stageManager;
  float _level;
  int _grade;
  long _seed;

  public this(Tunnel tunnel, Ship ship, ShotPool shots, BulletActorPool bullets,
              EnemyPool enemies, ParticlePool particles, FloatLetterPool floatLetters,
              StageManager stageManager) {
    this.tunnel = tunnel;
    this.ship = ship;
    this.shots = shots;
    this.bullets = bullets;
    this.enemies = enemies;
    this.particles = particles;
    this.floatLetters = floatLetters;
    this.stageManager = stageManager;
  }

  public abstract void start();
  public abstract void move();
  public abstract void draw(mat4 view);
  public abstract void drawLuminous(mat4 view);
  public abstract void drawFront(mat4 view);


  public float level(float v) {
    return _level = v;
  }

  public int grade(int v) {
    return _grade = v;
  }

  public long seed(long v) {
    return _seed = v;
  }
}

public class InGameState: GameState {
 private:
  static const int DEFAULT_EXTEND_SCORE = 100000;
  static const int MAX_EXTEND_SCORE = 500000;
  static const int DEFAULT_TIME = 120000;
  static const int MAX_TIME = 120000;
  static const int SHIP_DESTROYED_PENALTY_TIME = -15000;
  static const string SHIP_DESTROYED_PENALTY_TIME_MSG = "-15 SEC.";
  static const int EXTEND_TIME = 15000;
  static const string EXTEND_TIME_MSG = "+15 SEC.";
  static const int NEXT_ZONE_ADDITION_TIME = 30000;
  static const string NEXT_ZONE_ADDITION_TIME_MSG = "+30 SEC.";
  static const int NEXT_LEVEL_ADDITION_TIME = 45000;
  static const string NEXT_LEVEL_ADDITION_TIME_MSG = "+45 SEC.";
  static const int BEEP_START_TIME = 15000;
  Pad pad;
  PrefManager prefManager;
  GameManager gameManager;
  int score;
  int nextExtend;
  int time;
  int nextBeepTime;
  int startBgmCnt;
  string timeChangedMsg;
  int timeChangedShowCnt;
  int gameOverCnt;
  bool btnPressed;
  int pauseCnt;
  bool pausePressed;
  ReplayData _replayData;

  public this(Tunnel tunnel, Ship ship, ShotPool shots, BulletActorPool bullets,
              EnemyPool enemies, ParticlePool particles, FloatLetterPool floatLetters,
              StageManager stageManager,
              Pad pad, PrefManager prefManager, GameManager gameManager) {
    super(tunnel, ship, shots, bullets, enemies, particles, floatLetters, stageManager);
    this.pad = pad;
    this.prefManager = prefManager;
    this.gameManager = gameManager;
    _replayData = null;
  }

  public override void start() {
    Ship.replayMode = false;
    shots.clear();
    bullets.clear();
    enemies.clear();
    particles.clear();
    floatLetters.clear();
    RecordablePad rp = cast(RecordablePad) pad;
    rp.startRecord();
    _replayData = new ReplayData;
    _replayData.padRecord = rp.padRecord;
    _replayData.level = _level;
    _replayData.grade = _grade;
    _replayData.seed = _seed;
    Barrage.setRandSeed(_seed);
    Bullet.setRandSeed(_seed);
    Enemy.setRandSeed(_seed);
    FloatLetter.setRandSeed(_seed);
    Particle.setRandSeed(_seed);
    Shot.setRandSeed(_seed);
    SoundManager.setRandSeed(_seed);
    ship.start(_grade, _seed);
    stageManager.start(_level, _grade, _seed);
    initGameState();
    SoundManager.playBgm();
    startBgmCnt = -1;
    ship.setScreenShake(0, 0);
    gameOverCnt = 0;
    pauseCnt = 0;
    tunnel.setShipPos(0, 0, 0);
    tunnel.setSlices();
    SoundManager.enableSe();
  }

  public void initGameState() {
    score = 0;
    nextExtend = 0;
    setNextExtend();
    timeChangedShowCnt = -1;
    gotoNextZone(true);
  }

  public void gotoNextZone(bool isFirst = false) {
    clearVisibleBullets();
    if (isFirst) {
      time = DEFAULT_TIME;
      nextBeepTime = BEEP_START_TIME;
    } else {
      if (stageManager.middleBossZone) {
        changeTime(NEXT_ZONE_ADDITION_TIME, NEXT_ZONE_ADDITION_TIME_MSG);
      } else {
        changeTime(NEXT_LEVEL_ADDITION_TIME, NEXT_LEVEL_ADDITION_TIME_MSG);
        startBgmCnt = 90;
        SoundManager.fadeBgm();
      }
    }
  }

  public override void move() {
    if (pad.keys[SDLK_p] == SDL_PRESSED) {
      if (!pausePressed) {
        if (pauseCnt <= 0 && !ship.isGameOver)
          pauseCnt = 1;
        else
          pauseCnt = 0;
      }
      pausePressed = true;
    } else {
      pausePressed = false;
    }
    if (pauseCnt > 0) {
      pauseCnt++;
      return;
    }
    if (startBgmCnt > 0) {
      startBgmCnt--;
      if (startBgmCnt <= 0)
        SoundManager.nextBgm();
    }
    ship.move();
    stageManager.move();
    enemies.move();
    shots.move();
    bullets.move();
    particles.move();
    floatLetters.move();
    decrementTime();
    if (time < 0) {
      time = 0;
      if (!ship.isGameOver) {
        ship.isGameOver = true;
        btnPressed = true;
        SoundManager.fadeBgm();
        SoundManager.disableSe();
        prefManager.prefData.recordResult(cast(int) stageManager.level, score);
      }
      gameOverCnt++;
      int btn = pad.getButtonState();
      if (btn & Pad.Button.A) {
        if (gameOverCnt > 60 && !btnPressed) {
          gameManager.startTitle(true);
          return;
        }
        btnPressed = true;
      } else {
        btnPressed = false;
      }
      if (gameOverCnt > 1200)
        gameManager.startTitle();
    } else if (time <= nextBeepTime) {
      SoundManager.playSe("timeup_beep.wav");
      nextBeepTime -= 1000;
    }
  }

  public void decrementTime() {
    time -= 17;
    if (timeChangedShowCnt >= 0)
      timeChangedShowCnt--;
    if (ship.replayMode && time < 0)
      if (!ship.isGameOver)
        ship.isGameOver = true;
  }

  public override void draw(mat4 view) {
    glEnable(GL_CULL_FACE);
    tunnel.draw(view);
    glDisable(GL_CULL_FACE);
    particles.draw(view);
    enemies.draw(view);
    ship.draw(view);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    floatLetters.draw(view);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE);
    glDisable(GL_BLEND);
    bullets.draw(view);
    glEnable(GL_BLEND);
    shots.draw(view);
  }

  public override void drawLuminous(mat4 view) {
    particles.drawLuminous(view);
  }

  public override void drawFront(mat4 view) {
    ship.drawFront(view);
    Letter.drawNum(view, score, 610, 0, 15);
    Letter.drawString(view, "/", 510, 40, 7);
    Letter.drawNum(view, nextExtend - score, 615, 40, 7);
    if (time > BEEP_START_TIME)
      Letter.drawTime(view, time, 220, 24, 15);
    else
      Letter.drawTime(view, time, 220, 24, 15, 1);
    if (timeChangedShowCnt >= 0 && (timeChangedShowCnt % 64) > 32)
      Letter.drawString(view, timeChangedMsg, 250, 24, 7, Letter.Direction.TO_RIGHT, Letter.COLOR1);
    Letter.drawString(view, "LEVEL", 20, 410, 8, Letter.Direction.TO_RIGHT, Letter.COLOR1);
    Letter.drawNum(view, cast(int) stageManager.level, 135, 410, 8);
    if (ship.isGameOver)
      Letter.drawString(view, "GAME OVER", 140, 180, 20);
    if (pauseCnt > 0 && (pauseCnt % 64) < 32)
      Letter.drawString(view, "PAUSE", 240, 185, 17);
  }

  public void shipDestroyed() {
    clearVisibleBullets();
    changeTime(SHIP_DESTROYED_PENALTY_TIME, SHIP_DESTROYED_PENALTY_TIME_MSG);
  }

  public void clearVisibleBullets() {
    bullets.clearVisible();
  }

  public void addScore(int sc) {
    if (ship.isGameOver)
      return;
    score += sc;
    while (score > nextExtend) {
      setNextExtend();
      extendShip();
    }
  }

  private void setNextExtend() {
    float es = (cast(int) (stageManager.level * 0.5) + 10) * DEFAULT_EXTEND_SCORE / 10;
    if (es > MAX_EXTEND_SCORE)
      es = MAX_EXTEND_SCORE;
    nextExtend += es;
  }

  private void extendShip() {
    changeTime(EXTEND_TIME, EXTEND_TIME_MSG);
    SoundManager.playSe("extend.wav");
  }

  private void changeTime(int ct, string msg) {
    time += ct;
    if (time > MAX_TIME)
      time = MAX_TIME;
    nextBeepTime = (time / 1000) * 1000;
    if (nextBeepTime > BEEP_START_TIME)
      nextBeepTime = BEEP_START_TIME;
    timeChangedShowCnt = 240;
    timeChangedMsg = msg;
  }

  public void saveReplay(string fileName) {
    _replayData.save(fileName);
  }

  public void loadReplay(string fileName) {
    _replayData = new ReplayData;
    _replayData.load(fileName);
  }

  public void resetReplay() {
    _replayData = null;
  }

  public ReplayData replayData() {
    return _replayData;
  }
}

public class TitleState: GameState {
 private:
  Pad pad;
  TitleManager titleManager;
  EnemyPool passedEnemies;
  InGameState inGameState;
  ReplayData replayData;
  int gameOverCnt;

  public this(Tunnel tunnel, Ship ship, ShotPool shots, BulletActorPool bullets,
              EnemyPool enemies, ParticlePool particles, FloatLetterPool floatLetters,
              StageManager stageManager,
              Pad pad,
              TitleManager titleManager,
              EnemyPool passedEnemies,
              InGameState inGameState) {
    super(tunnel, ship, shots, bullets, enemies, particles, floatLetters, stageManager);
    this.pad = pad;
    this.titleManager = titleManager;
    this.passedEnemies = passedEnemies;
    this.inGameState = inGameState;
  }

  public void close() {
    titleManager.close();
  }

  public void setReplayData(ReplayData rd) {
    replayData = rd;
  }

  public override void start() {
    SoundManager.haltBgm();
    SoundManager.disableSe();
    titleManager.start();
    clearAll();
    if (replayData)
      startReplay();
  }

  private void clearAll() {
    shots.clear();
    bullets.clear();
    enemies.clear();
    particles.clear();
    floatLetters.clear();
    passedEnemies.clear();
  }

  private void startReplay() {
    Ship.replayMode = true;
    RecordablePad rp = cast(RecordablePad) pad;
    rp.startReplay(replayData.padRecord);
    _level = replayData.level;
    _grade = replayData.grade;
    _seed = replayData.seed;
    Barrage.setRandSeed(_seed);
    Bullet.setRandSeed(_seed);
    Enemy.setRandSeed(_seed);
    FloatLetter.setRandSeed(_seed);
    Particle.setRandSeed(_seed);
    Shot.setRandSeed(_seed);
    SoundManager.setRandSeed(_seed);
    ship.start(_grade, _seed);
    stageManager.start(_level, _grade, _seed);
    inGameState.initGameState();
    ship.setScreenShake(0, 0);
    gameOverCnt = 0;
    tunnel.setShipPos(0, 0, 0);
    tunnel.setSlices();
    tunnel.setSlicesBackward();
  }

  public override void move() {
    if (ship.isGameOver) {
      gameOverCnt++;
      if (gameOverCnt > 120) {
        clearAll();
        startReplay();
      }
    }
    if (replayData) {
      ship.move();
      stageManager.move();
      enemies.move();
      shots.move();
      bullets.move();
      particles.move();
      floatLetters.move();
      passedEnemies.move();
      inGameState.decrementTime();
      titleManager.move(true);
    } else {
      titleManager.move(false);
    }
  }

  public override void draw(mat4 view) {
    if (replayData) {
      float rcr = titleManager.replayChangeRatio * 2.4f;
      if (rcr > 1)
        rcr = 1;
      glViewport(0, 0,
                 cast(int) (Screen.width / 4 * (3 + rcr)),
                 Screen.height);
      glEnable(GL_CULL_FACE);
      tunnel.draw(view);
      tunnel.drawBackward(view);
      glDisable(GL_CULL_FACE);
      particles.draw(view);
      enemies.draw(view);
      passedEnemies.draw(view);
      ship.draw(view);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
      floatLetters.draw(view);
      glBlendFunc(GL_SRC_ALPHA, GL_ONE);
      glDisable(GL_BLEND);
      bullets.draw(view);
      glEnable(GL_BLEND);
      shots.draw(view);
    }

    mat4 titleView = Screen.screenResized();
    titleManager.draw(titleView);
  }

  public override void drawLuminous(mat4 view) {
  }

  public override void drawFront(mat4 view) {
    titleManager.drawFront(view);
    if (!ship.drawFrontMode || titleManager.replayChangeRatio < 1)
      return;
    inGameState.drawFront(view);
  }
}
