import "./DominumJetton";

struct MinerInfo {
  last_claim: Int;
  booster: Address?;
}

contract DominumMining {
  // 📦 Основные адреса
  master: Address;
  pool: Address;
  start_time: Int;

  // 🧱 Состояние
  map<Address, MinerInfo> miners;

  // 🔧 Инициализация
  init(master: Address, pool: Address) {
    self.master = master;
    self.pool = pool;
    self.start_time = now();
  }

  // 🧩 Установка бустера вручную
  receive("SetBooster") {
    let ctx = context();
    let info = self.miners[ctx.sender] ?? MinerInfo {
      last_claim: 0,
      booster: null
    };

    let slice = ctx.body;
    let booster: Address = slice.loadAddress();

    self.miners[ctx.sender] = MinerInfo {
      last_claim: info.last_claim,
      booster: booster
    };
  }

  // 🚜 Майнинг: 2 месяца каждый день, далее каждые 72 часа
  receive("Mine") {
    let ctx = context();
    let now = now();

    let info = self.miners[ctx.sender] ?? MinerInfo {
      last_claim: 0,
      booster: null
    };

    let elapsed: Int = now - self.start_time;
    let seconds_in_month: Int = 30 * 86400;

    let min_interval: Int = elapsed <= 2 * seconds_in_month ? 86400 : 3 * 86400;
    require(now - info.last_claim >= min_interval, "Claim too soon");

    let baseReward = self.calculateBaseReward();
    let boost = 100;

    if (info.booster != null) {
      boost = self.getBoost(info.booster!!);
    }

    let fullReward: Int = baseReward * boost / 100;
    let poolFee: Int = fullReward * 25 / 100;
    let userReward: Int = fullReward - poolFee;

    self.miners[ctx.sender] = MinerInfo {
      last_claim: now,
      booster: info.booster
    };

    // 🪙 Отправляем награду пользователю
    send(SendParameters {
      to: self.master,
      value: ton("0.1"),
      bounce: true,
      body: MintMining {
        amount: userReward,
        receiver: ctx.sender
      }.toCell()
    });

    // 🪣 Комиссия пула
    send(SendParameters {
      to: self.master,
      value: ton("0.1"),
      bounce: true,
      body: MintMining {
        amount: poolFee,
        receiver: self.pool
      }.toCell()
    });
  }

  // 🧮 Формула буста по типу NFT
  fun getBoost(nft: Address): Int {
    if (nft == LEGENDARY) {
      return 1000; // x10.0
    } else if (nft == EPIC) {
      return 700;
    } else if (nft == EXCELLENT) {
      return 500;
    } else if (nft == GOOD) {
      return 300;
    } else if (nft == NORMAL) {
      return 150;
    }
    return 100;
  }

  // 📉 Расчёт награды
  fun calculateBaseReward(): Int {
    let elapsed: Int = now() - self.start_time;
    let seconds_in_month: Int = 30 * 86400;

    if (elapsed <= seconds_in_month) {
      return 100000;
    } else if (elapsed <= 2 * seconds_in_month) {
      return 50000;
    } else {
      let five_years_sec: Int = 5 * 365 * 86400;
      let passed_since_month2: Int = elapsed - 2 * seconds_in_month;
      let ratio: Float = 1.0 - (passed_since_month2.toFloat() / five_years_sec.toFloat());
      let decayed: Float = 5000.0 * pow(ratio, 3.0);
      let final_reward: Int = max(decayed.toInt(), 1); // минимум 0.01 jetton
      return final_reward;
    }
  }

  // 🛡 Кто имеет право вызывать MintMining в DominumJetton
  get fun get_authorized_minter(): Address {
    return myAddress();
  }
}
