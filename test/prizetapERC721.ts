import axios from 'axios'
import { expect } from "chai";
import { ethers } from 'hardhat';
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { time } from '@nomicfoundation/hardhat-network-helpers';

import { ERC721Test, MuonClient, PrizetapERC721Raffle } from "../typechain-types";
import { BigNumberish, BigNumber } from 'ethers';

const getDummyParticipationSig = async (
  contractAddress: string,
  wallet: string,
  raffleId: number,
  multiplier: number
) => {
  const network = await ethers.provider.getNetwork();
  const response = await axios.get(
    `http://localhost:3000/v1/?app=local_unitap&method=raffle-entry&params[chain]=${network.chainId}&params[contract]=${contractAddress}&params[wallet]=${wallet}&params[raffleId]=${raffleId}&params[multiplier]=${multiplier}`
  );
  return response.data;
};

const getDummyRandomWordsSig = async (
  randomWords: number[],
  expirationTime: number|null = null
) => {
  expirationTime = expirationTime == null ? await time.latest() + 600 : expirationTime
  const response = await axios.get(
    `http://localhost:3000/v1/?app=local_unitap&method=random-words&params[randomWords]=${randomWords.join(',')}&params[expirationTime]=${expirationTime}`
  );
  return response.data;
};

describe("PrizetapERC721Raffle", function () {
  const ONE = ethers.utils.parseEther("1");
  const muonAppId =
  "36008207045166041889541988837940940609790145981638029194585485977405695308515";
  const muonPublicKey = {
    x: "0x60d24ba781e8cb6242ea6865d515c50a098be1052878a604a90613fd0d3712dc",
    parity: 1,
  };

  let deployer: SignerWithAddress;
  let admin: SignerWithAddress;
  let operator: SignerWithAddress;
  let collection: ERC721Test;
  let muon: MuonClient;
  let prizetap: PrizetapERC721Raffle;
  let initiator1: SignerWithAddress;
  let initiator2: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let user4: SignerWithAddress;
  let user5: SignerWithAddress;
  let user6: SignerWithAddress;

  const participateInRaffle = async (
    user: SignerWithAddress, 
    raffleId: BigNumberish,
    multiplier: BigNumberish,
    sig: any
  ) => {
    await prizetap.connect(user).participateInRaffle(
      raffleId,
      multiplier,
      sig["result"]["reqId"],
      {
        signature: sig["result"]["signatures"][0]["signature"],
        owner: sig["result"]["signatures"][0]["owner"],
        nonce: sig["result"]["data"]["init"]["nonceAddress"]
      },
      sig["result"]["shieldSignature"]
    )
  }

  const setRandomNumbers = async (
    raffleId: number,
    sig: any
  ) => {
    await prizetap.connect(operator).setRaffleRandomNumbers(
      raffleId,
      sig["result"]["data"]["result"]["expirationTime"],
      sig["result"]["data"]["result"]["randomWords"],
      sig["result"]["reqId"],
      {
        signature: sig["result"]["signatures"][0]["signature"],
        owner: sig["result"]["signatures"][0]["owner"],
        nonce: sig["result"]["data"]["init"]["nonceAddress"]
      },
      sig["result"]["shieldSignature"]
    )
  }

  before(async () => {
    [
      deployer,
      admin,
      operator,
      initiator1,
      initiator2,
      user1,
      user2,
      user3,
      user4,
      user5,
      user6
    ] = await ethers.getSigners();

    const collectionFactory = await ethers.getContractFactory("ERC721Test");
    collection = await collectionFactory.connect(deployer).deploy(
      "MetaMartianNFT",
      "MMN",
      ""
    );
    await collection.deployed();

    await collection.connect(deployer).mint(initiator1.address, 1);
    await collection.connect(deployer).mint(initiator1.address, 2);
    await collection.connect(deployer).mint(initiator1.address, 3);
    await collection.connect(deployer).mint(initiator1.address, 4);
    await collection.connect(deployer).mint(initiator1.address, 5);

    await collection.connect(deployer).mint(initiator2.address, 6);
    await collection.connect(deployer).mint(initiator2.address, 7);

    const muonFactory = await ethers.getContractFactory("MuonClient");
    muon = await muonFactory.connect(deployer).deploy(
      muonAppId,
      muonPublicKey
    );
    await muon.deployed();

    const prizetapFactory = await ethers.getContractFactory("PrizetapERC721Raffle");
    prizetap = await prizetapFactory.connect(deployer).deploy(
      muonAppId,
      muonPublicKey,
      muon.address,
      "0x4d7A51Caa1E79ee080A7a045B61f424Da8965A3c",
      admin.address,
      operator.address
    ) as PrizetapERC721Raffle;
    await prizetap.deployed();

    await prizetap.connect(admin).setValidationPeriod(0);
    await collection.connect(initiator1).approve(prizetap.address, 1);
    await collection.connect(initiator1).approve(prizetap.address, 2);
    await collection.connect(initiator1).approve(prizetap.address, 3);

    await collection.connect(initiator2).approve(prizetap.address, 6);
    await collection.connect(initiator2).approve(prizetap.address, 7);
  
    const now = await time.latest();
    await prizetap.connect(initiator1).createRaffle(
      collection.address,
      [1,2,3],
      5,
      10,
      now + 5,
      now + 180,
      3,
      `0x${"0".repeat(64)}`
    );
    
    await prizetap.connect(initiator2).createRaffle(
      collection.address,
      [6,7],
      1000,
      10,
      now + 20,
      now + 30,
      2,
      `0x${"0".repeat(64)}`
    );

  });

  beforeEach(async () => {
    // await usdc.mint(initiator1.address, ONE.mul(100));

    // await usdc.connect(initiator1).approve(prizetap.address, ONE.mul(100));
  });

  describe("Create raffle", async function () {
    it("Should create raffle successfully", async function () {
      expect(await collection.ownerOf(1)).to.eq(prizetap.address);
      expect(await collection.ownerOf(2)).to.eq(prizetap.address);
      expect(await collection.ownerOf(3)).to.eq(prizetap.address);

      const raffle = await prizetap.raffles(1);
      expect(raffle.initiator).to.eq(initiator1.address);
      expect(raffle.collection).to.eq(collection.address);
      expect(raffle.maxParticipants).to.eq(5);
      expect(raffle.maxMultiplier).to.eq(10);
      // expect(raffle.startTime).to.eq(now + 20);
      // expect(raffle.endTime).to.eq(now + 1800);
      expect(raffle.lastParticipantIndex).to.eq(0);
      expect(raffle.lastWinnerIndex).to.eq(0);
      expect(raffle.participantsCount).to.eq(0);
      expect(raffle.winnersCount).to.eq(3);
      expect(raffle.exists).to.eq(true);
      expect(raffle.status).to.eq(0);
      
    });

    it("Should not create raffle with invalid winners count", async function () {
      const now = await time.latest();
      await expect(prizetap.connect(initiator1).createRaffle(
        collection.address,
        [1],
        1000,
        10,
        now + 5,
        now + 1800,
        501,
        `0x${"0".repeat(64)}`
      )).to.be.revertedWith("Invalid winnersCount");

      await expect(prizetap.connect(initiator1).createRaffle(
        collection.address,
        [1],
        20,
        10,
        now + 5,
        now + 1800,
        21,
        `0x${"0".repeat(64)}`
      )).to.be.revertedWith("Invalid winnersCount");
      
    });

    it("Should not create raffle with invalid deposit amount", async function () {
      const now = await time.latest();
      await expect(prizetap.connect(initiator1).createRaffle(
        collection.address,
        [1],
        10,
        10,
        now + 5,
        now + 1800,
        5,
        `0x${"0".repeat(64)}`
      )).to.be.revertedWith("tokenIds length mismatch with winnersCount");

      await expect(prizetap.connect(initiator1).createRaffle(
        collection.address,
        [4,5],
        10,
        10,
        now + 5,
        now + 1800,
        2,
        `0x${"0".repeat(64)}`
      )).to.be.revertedWith("ERC721: caller is not token owner or approved");
      
    });
  });

  describe("Participate in raffle", async function() {
    it("Should prevent the participation in a raffle which is not started yet", 
      async function () {
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user1.address,
        2,
        5
      );
      await expect(participateInRaffle(user1, 2, 5, sig))
        .to.be.revertedWith("Raffle is not started");
    });

    it("Should participate in raffle successfully", async function () {
      await time.increase(10);
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user1.address,
        1,
        5
      );
      // console.log(sig["result"])
      await participateInRaffle(user1, 1, 5, sig);
      const raffle = await prizetap.raffles(1);
      expect(raffle.lastParticipantIndex).to.eq(5);
      expect(raffle.participantsCount).to.eq(1);
      expect(await prizetap.getParticipants(1, 1, 5))
        .to.deep.equal(Array(5).fill(user1.address));
    });

    it("Should prevent participation in raffle with multiplier greater than maxMultiplier", 
      async function () {
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user2.address,
        1,
        11
      );
      await expect(participateInRaffle(user2, 1, 11, sig))
        .to.be.revertedWith("Invalid multiplier");
    });

    it("Should prevent participation in raffle with invalid signature", 
      async function () {
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user2.address,
        1,
        6
      );
      await expect(participateInRaffle(user3, 1, 6, sig))
        .to.be.revertedWith("Invalid signature!");
    });

    it("Should prevent manipulating the multiplier", 
      async function () {
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user3.address,
        1,
        6
      );
      await expect(participateInRaffle(user3, 1, 7, sig))
        .to.be.revertedWith("Invalid signature!");
    });

    it("Should prevent manipulating the raffleId", 
      async function () {
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user3.address,
        1,
        6
      );
      await expect(participateInRaffle(user3, 2, 6, sig))
        .to.be.revertedWith("Invalid signature!");
    });

    it("Should prevent repeating the participation in a raffle", 
      async function () {
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user1.address,
        1,
        6
      );
      await expect(participateInRaffle(user1, 1, 6, sig))
        .to.be.revertedWith("Already participated");
    });

    it("Should prevent the participation in a raffle which is ended", 
      async function () {
      await time.increase(10)
      const sig = await getDummyParticipationSig(
        prizetap.address,
        user1.address,
        2,
        5
      );
      await expect(participateInRaffle(user1, 2, 5, sig))
        .to.be.revertedWith("Raffle time is up");
    });

    it("Should not participate in a raffle when the maxParticipants is reached", 
      async function () {
      let sig = await getDummyParticipationSig(
        prizetap.address,
        user2.address,
        1,
        1
      );
      await participateInRaffle(user2, 1, 1, sig);
      sig = await getDummyParticipationSig(
        prizetap.address,
        user3.address,
        1,
        1
      );
      await participateInRaffle(user3, 1, 1, sig);
      sig = await getDummyParticipationSig(
        prizetap.address,
        user4.address,
        1,
        1
      );
      await participateInRaffle(user4, 1, 1, sig);
      sig = await getDummyParticipationSig(
        prizetap.address,
        user5.address,
        1,
        1
      );
      await participateInRaffle(user5, 1, 1, sig);
      sig = await getDummyParticipationSig(
        prizetap.address,
        user6.address,
        1,
        1
      );
      await expect(participateInRaffle(user6, 1, 1, sig))
        .to.be.revertedWith("The maximum number of participants has been reached");
    });
  });

  describe("Set raffle random numbers", async function() {
    it("Should not set raffle randomWords when raffle has not ended", 
      async function () {
      const sig = await getDummyRandomWordsSig(
        [11,1,10,4,2]
      );
      await expect(setRandomNumbers(1, sig))
        .to.be.revertedWith("The raffle time has not ended");
    });

    it("Should not set raffle randomWords when raffle has no participant", 
      async function () {
      const sig = await getDummyRandomWordsSig(
        [11,1,10,4,2]
      );
      await expect(setRandomNumbers(2, sig))
        .to.be.revertedWith("There is no participant in raffle");
    });

    it("Should not set the invalid number of randomWords", 
      async function () {
      await time.increase(180);
      const sig = await getDummyRandomWordsSig(
        [11,1,10,4]
      );
      await expect(setRandomNumbers(1, sig))
        .to.be.revertedWith("Invalid number of random words");
    });

    it("Should not set the expired randomWords", 
      async function () {
      const sig = await getDummyRandomWordsSig(
        [11,1,10,4],
        await time.latest()
      );
      await expect(setRandomNumbers(1, sig))
        .to.be.revertedWith("Invalid number of random words");
    });

    it("Should not set raffle randomWords when contract is paused", 
      async function () {
      const sig = await getDummyRandomWordsSig(
        [11,1,10,4,2]
      );
      await prizetap.connect(admin).pause();
      await expect(setRandomNumbers(1, sig))
        .to.be.revertedWith("Pausable: paused");
        await prizetap.connect(admin).unpause();
    });

    it("Should set raffle randomWords successfully", 
      async function () {
      const sig = await getDummyRandomWordsSig(
        [11,1,10]
      );
      await expect(setRandomNumbers(1, sig)).to.not.be.reverted;
    });

    it("Should not overwrite raffle randomWords", 
      async function () {
      const sig = await getDummyRandomWordsSig(
        [11,1,10]
      );
      await expect(setRandomNumbers(1, sig))
        .to.be.revertedWith("The random numbers are already set");
    });
  });

  describe("Set winners", async function() {
    
    before(async function() {
      await collection.mint(initiator1.address, 8);
      await collection.mint(initiator1.address, 9);
      await collection.mint(initiator1.address, 10);
      await collection.connect(initiator1).approve(prizetap.address, 8);
      await collection.connect(initiator1).approve(prizetap.address, 9);
      await collection.connect(initiator1).approve(prizetap.address, 10);
      const now = await time.latest()
      await prizetap.connect(initiator1).createRaffle(
        collection.address,
        [8,9,10],
        50,
        10,
        now + 5,
        now + 100,
        3,
        `0x${"0".repeat(64)}`
      );
      await time.increase(6);

      let sig = await getDummyParticipationSig(
        prizetap.address,
        user1.address,
        3,
        6
      );
      await participateInRaffle(user1, 3, 6, sig);

      sig = await getDummyParticipationSig(
        prizetap.address,
        user2.address,
        3,
        1
      );
      await participateInRaffle(user2, 3, 1, sig);

      sig = await getDummyParticipationSig(
        prizetap.address,
        user3.address,
        3,
        2
      );
      await participateInRaffle(user3, 3, 2, sig);

      sig = await getDummyParticipationSig(
        prizetap.address,
        user4.address,
        3,
        10
      );
      await participateInRaffle(user4, 3, 10, sig);

      sig = await getDummyParticipationSig(
        prizetap.address,
        user5.address,
        3,
        1
      );
      await participateInRaffle(user5, 3, 1, sig);
    });

    it("Should not set the non-existing raffle winners", 
      async function () {
      await expect(prizetap.setWinners(4, 5))
        .to.be.revertedWith("The raffle does not exist");
    });

    it("Should not set winners when raffle has not ended", 
      async function () {
      await expect(prizetap.setWinners(3, 5))
        .to.be.revertedWith("The raffle time has not ended");
    });

    it("Should not set winners when raffle has no participant", 
      async function () {
      await expect(prizetap.setWinners(2, 5))
        .to.be.revertedWith("There is no participant in raffle");
    });

    it("Should not set winners when the random words are not set", 
      async function () {
      await time.increase(100)
      await expect(prizetap.setWinners(3, 5))
        .to.be.revertedWith("Random numbers are not set");
    });

    it("Should not set winners with invalid toId", 
      async function () {
      const sig = await getDummyRandomWordsSig(
        [48, 112, 36]
      );
      await setRandomNumbers(3, sig);

      await expect(prizetap.setWinners(3, 5))
        .to.be.revertedWith("Invalid toId");
    });

    it("Should set winners correctly", 
      async function () {
      expect(await prizetap.isWinner(3, user1.address)).to.eq(false);
      expect(await prizetap.isWinner(3, user3.address)).to.eq(false);
      expect(await prizetap.isWinner(3, user4.address)).to.eq(false);

      await prizetap.setWinners(3, 1);

      let raffle = await prizetap.raffles(3);
      expect(raffle.lastWinnerIndex).to.eq(1);
      expect(raffle.lastParticipantIndex).to.eq(20);
      expect(raffle.status).to.eq(0);

      let winners = await prizetap.getWinners(3, 1, 2);
      expect(winners).to.deep.eq([user3.address]);

      expect(await prizetap.isWinner(3, user3.address)).to.eq(true);
      expect(await prizetap.isWinnerClaimed(3, user3.address)).to.eq(false);

      expect(await prizetap.lastNotWinnerIndexes(3)).to.eq(18);

      expect(await prizetap.raffleWinners(3, 1)).to.eq(user3.address);
      expect(await prizetap.raffleWinners(3, 2)).to.eq(ethers.constants.AddressZero);

      let participants = await prizetap.getParticipants(3, 1, 20);
      expect(participants).to.deep.eq([user1.address,
        user1.address,
        user1.address,
        user1.address,
        user1.address,
        user1.address,
        user2.address,
        user5.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user3.address,
        user3.address
      ]);

      await expect(prizetap.setWinners(3, 1)).to.be.revertedWith("Invalid toId");
      await prizetap.setWinners(3, 3);

      raffle = await prizetap.raffles(3);
      expect(raffle.lastWinnerIndex).to.eq(3);
      expect(raffle.lastParticipantIndex).to.eq(20);
      expect(raffle.status).to.eq(1);

      winners = await prizetap.getWinners(3, 1, 3);
      expect(winners).to.deep.eq([user3.address, user1.address, user4.address]);

      expect(await prizetap.isWinner(3, user1.address)).to.eq(true);
      expect(await prizetap.isWinner(3, user4.address)).to.eq(true);
      expect(await prizetap.isWinnerClaimed(3, user1.address)).to.eq(false);
      expect(await prizetap.isWinnerClaimed(3, user4.address)).to.eq(false);

      expect(await prizetap.lastNotWinnerIndexes(3)).to.eq(2);

      expect(await prizetap.raffleWinners(3, 2)).to.eq(user1.address);
      expect(await prizetap.raffleWinners(3, 3)).to.eq(user4.address);

      participants = await prizetap.getParticipants(3, 1, 20);
      expect(participants).to.deep.eq([
        user2.address,
        user5.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user4.address,
        user1.address,
        user1.address,
        user1.address,
        user1.address,
        user1.address,
        user1.address,
        user3.address,
        user3.address
      ]);

      expect(await prizetap.participantPositions(3, user1.address, 0)).to.eq(18);
      expect(await prizetap.participantPositions(3, user1.address, 5)).to.eq(13);
      expect(await prizetap.participantPositions(3, user4.address, 0)).to.eq(12);
      expect(await prizetap.participantPositions(3, user4.address, 9)).to.eq(3);

      await expect(prizetap.setWinners(3, 3))
        .to.be.revertedWith("The raffle is not open");
      
    });
  });

  describe("Claim reward", async function() {
    it("Should not allow the non-winner to claim the prize", 
      async function () {
        await expect(prizetap.connect(user2).claimPrize(3))
          .to.be.revertedWith("You are not winner!");
    });
    
    it("Should allow the winner to claim the prize", 
      async function () {
        expect(await collection.ownerOf(8))
          .to.eq(prizetap.address);

        await prizetap.connect(user3).claimPrize(3);

        expect(await collection.ownerOf(8))
          .to.eq(user3.address);
    });

    it("Should not allow the winner to repeat claiming", 
      async function () {
        await expect(prizetap.connect(user3).claimPrize(3))
          .to.be.revertedWith("You already claimed the prize!");
    });
  });

  describe("Reject raffle", async function() {

    it("Should allow the admin to reject a raffle", 
      async function () {
        await collection.connect(initiator1).approve(prizetap.address, 4);
        const now = await time.latest();
        await prizetap.connect(initiator1).createRaffle(
          collection.address,
          [4],
          1000,
          10,
          now + 5,
          now + 1800,
          1,
          `0x${"0".repeat(64)}`
        );
        let raffle = await prizetap.raffles(4);
        expect(raffle.status).to.eq(0);
        expect(raffle.exists).to.eq(true);
        await expect(prizetap.connect(admin).rejectRaffle(4)).not.be.reverted;
        raffle = await prizetap.raffles(4);
        expect(raffle.status).to.eq(2);
    });

    it("Should allow the operator to reject a raffle", 
      async function () {
        await collection.connect(initiator1).approve(prizetap.address, 5);
        const now = await time.latest();
        await prizetap.connect(initiator1).createRaffle(
          collection.address,
          [5],
          1000,
          10,
          now + 5,
          now + 6,
          1,
          `0x${"0".repeat(64)}`
        );
        let raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(0);
        expect(raffle.exists).to.eq(true);
        await expect(prizetap.connect(operator).rejectRaffle(5)).not.be.reverted;
        raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(2);
    });
    
    it("Should not allow the non-operator and non-admin to reject a raffle", 
      async function () {
        await collection.mint(initiator1.address, 11);
        await collection.mint(initiator1.address, 12);
        await collection.connect(initiator1).approve(prizetap.address, 11);
        await collection.connect(initiator1).approve(prizetap.address, 12);

        const now = await time.latest();
        await prizetap.connect(initiator1).createRaffle(
          collection.address,
          [11, 12],
          1000,
          10,
          now + 5,
          now + 50,
          2,
          `0x${"0".repeat(64)}`
        );
        let raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
        expect(raffle.exists).to.eq(true);
        await expect(prizetap.connect(user1).rejectRaffle(6))
          .to.be.revertedWith("Permission denied!");
        raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
    });

    it("Should not allow the admin to reject a raffle which is not open", 
      async function () {
        let raffle = await prizetap.raffles(4);
        expect(raffle.status).to.eq(2);
        await expect(prizetap.connect(admin).rejectRaffle(4))
          .to.be.revertedWith("The raffle is not open");
        raffle = await prizetap.raffles(4);
        expect(raffle.status).to.eq(2);
    });

    it("Should not allow the admin to reject a raffle which has some participants", 
      async function () {
        await time.increase(5);
        const sig = await getDummyParticipationSig(
          prizetap.address,
          user1.address,
          6,
          5
        );
        await participateInRaffle(user1, 6, 5, sig);
        let raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
        await expect(prizetap.connect(admin).rejectRaffle(6))
          .to.be.revertedWith("Raffle's participants count > 0");
        raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
    });
  });

  describe("Refund prize", async function() {
    it("Should not allow the non-initiator to refund the prize", 
      async function () {
        let raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(2);
        await expect(prizetap.connect(initiator2).refundPrize(5))
          .to.be.revertedWith("Permission denied!");
        raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(2);
    });

    it("Should not allow the initiator to refund the prize when the raffle is not rejected or ended yet", 
      async function () {
        await collection.connect(deployer).mint(initiator2.address, 13);
        await collection.connect(initiator2).approve(prizetap.address, 13);
        const now = await time.latest();
        await prizetap.connect(initiator2).createRaffle(
          collection.address,
          [13],
          1000,
          10,
          now + 5,
          now + 180,
          1,
          `0x${"0".repeat(64)}`
        );
        let raffle = await prizetap.raffles(7);
        expect(raffle.status).to.eq(0);
        await expect(prizetap.connect(initiator2).refundPrize(7))
          .to.be.revertedWith("The raffle is not rejected or expired");
        raffle = await prizetap.raffles(7);
        expect(raffle.status).to.eq(0);
    });

    it("Should not allow the initiator to refund the prize when the raffle has some participants", 
      async function () {
        let raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
        await expect(prizetap.connect(initiator1).refundPrize(6))
          .to.be.revertedWith("participants > 0");
        raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
    });

    it("Should allow the initiator to refund the prize", 
      async function () {
        let raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(2);
        expect(await collection.ownerOf(5)).to.eq(prizetap.address);
        await expect(prizetap.connect(initiator1).refundPrize(5))
          .not.to.be.reverted;
        expect(await collection.ownerOf(5)).to.eq(initiator1.address);
        raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(3);
    });

    it("Should not allow the initiator to repeat refunding the prize", 
      async function () {
        let raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(3);
        await expect(prizetap.connect(initiator1).refundPrize(5))
          .to.be.revertedWith("The raffle is already refunded");
        raffle = await prizetap.raffles(5);
        expect(raffle.status).to.eq(3);
    });

    it("Should not allow the initiator refund the remaining prizes when the raffle is not closed yet", 
      async function () {
        let raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
        await expect(prizetap.connect(initiator1).refundRemainingPrizes(6))
          .to.be.revertedWith("The raffle is not closed");
        raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(0);
    });

    it("Should not allow the non-initiator refund the remaining prizes", 
      async function () {
        await time.increase(50);
        const sig = await getDummyRandomWordsSig(
          [1, 1]
        );
        await setRandomNumbers(6, sig);
        await prizetap.setWinners(6, 2);
        expect(await prizetap.getWinners(6, 1, 2)).to.deep.eq([
          user1.address, ethers.constants.AddressZero
        ]);
        let raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(1);
        await expect(prizetap.connect(initiator2).refundRemainingPrizes(6))
          .to.be.revertedWith("Permission denied!");
        raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(1);
    });

    it("Should allow the initiator refund the remaining prizes", 
      async function () {
        let raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(1);
        expect(await collection.ownerOf(11)).to.eq(prizetap.address);
        expect(await collection.ownerOf(12)).to.eq(prizetap.address);
        await expect(prizetap.connect(initiator1).refundRemainingPrizes(6))
          .not.to.be.reverted;
        expect(await collection.ownerOf(11)).to.eq(initiator1.address);
        expect(await collection.ownerOf(12)).to.eq(prizetap.address);
        raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(3);
    });

    it("Should not allow the initiator repeat the refund of remaining prizes", 
      async function () {
        let raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(3);
        await expect(prizetap.connect(initiator1).refundRemainingPrizes(6))
          .to.be.revertedWith("The raffle is not closed");
        raffle = await prizetap.raffles(6);
        expect(raffle.status).to.eq(3);
    });

    it("Should not allow the initiator refund the remaining prizes when the participants is not less than winners", 
      async function () {
        let raffle = await prizetap.raffles(1);
        expect(raffle.status).to.eq(0);
        await expect(prizetap.connect(initiator1).refundRemainingPrizes(1))
          .to.be.revertedWith("participants > winners");
        raffle = await prizetap.raffles(1);
        expect(raffle.status).to.eq(0);
    });
  });

});