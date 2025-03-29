// npx blueprint build

// DominumMining.tact

import "./DominumJetton";
import "./messages";


struct MinerInfo {
  last_claim: Int;
  booster: Address?;
}

contract DominumMining {
  master: Address;
  pool: Address;
  start_time: Int;
  data: Cell; 

  init(master: Address, pool: Address) {
    self.master = master;
    self.pool = pool;
    self.start_time = now();
    self.data = emptyCell();
  }

  receive(msg: SetBooster) {
    let ctx = context();

    // Загружаем словарь
    let dict = self.data.beginParse().loadDict(Address, Cell);
    let minerCell = dict.get(ctx.sender);

    // Достаём старое состояние майнера или создаём новое
    let info: MinerInfo = minerCell == null
      ? MinerInfo { last_claim: 0, booster: null }
      : minerCell!!.beginParse().decode(MinerInfo);

    // Обновляем информацию
    let updated = MinerInfo {
      last_claim: info.last_claim,
      booster: msg.booster
    }.toCell();

    // Сохраняем обратно в словарь
    let newDict = dict.set(ctx.sender, updated);
    self.data = beginCell().storeDict(newDict).endCell();
  }

  receive("Mine") {
    let ctx = context();
    let ts = now();

    let dict = self.data.beginParse().loadDict(Address, Cell);
    let minerCell = dict.get(ctx.sender);

    let info: MinerInfo = (
  minerCell == null
    ? MinerInfo { last_claim: 0, booster: null }
    : minerCell!!.beginParse().decode(MinerInfo)
);


    let elapsed: Int = ts - self.start_time;
    let seconds_in_month: Int = 30 * 86400;
    let min_interval: Int = elapsed <= 2 * seconds_in_month ? 86400 : 3 * 86400;
    require(ts - info.last_claim >= min_interval, "Claim too soon");

    let baseReward = self.calculateBaseReward();
    let boost = info.booster != null ? self.getBoost(info.booster!!) : 100;

    let fullReward: Int = baseReward * boost / 100;
    let poolFee: Int = fullReward * 25 / 100;
    let userReward: Int = fullReward - poolFee;

    let updated = MinerInfo {
      last_claim: ts,
      booster: info.booster
    }.toCell();

    let newDict = dict.set(ctx.sender, updated);
    self.data = beginCell().storeDict(newDict).endCell();

    send(SendParameters {
      to: self.master,
      value: ton("0.1"),
      bounce: true,
      body: MintMining {
        amount: userReward,
        receiver: ctx.sender
      }.toCell()
    });

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

  fun getBoost(nft: Address): Int {
    if (nft == LEGENDARY) {
      return 1000;
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
      let ratio = 1 - passed_since_month2 * 10000 / five_years_sec; // целочисленная арифметика
      let ratioCubed = ratio * ratio * ratio / 100000000;
      let decayed = 5000 * ratioCubed / 100;
      return max(decayed, 1);
    }
  }

  get fun get_authorized_minter(): Address {
    return myAddress();
  }
}
