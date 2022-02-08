const ThriftManager = artifacts.require("ThriftManager");

contract("Thriftmanager", accounts => {
    it("should deploy with the correct admin contrib", () => {
        return ThriftManager.deployed()
        .then(thriftInstance => {
            return thriftInstance.admin.call()
        })
        .then(admin => assert.equal(admin, accounts[0], "Admin account not correctly set"));
    });

    it("should create a new thrift with the correct details", () => {
        let thriftInstance;

        const maxParticipants = 2;
        const roundAmount = 50;
        const roundPeriodHrs = 1;
        const roundPeriodSecs = roundPeriodHrs * 60 * 60;
        const minStake = maxParticipants * roundAmount;

        return ThriftManager.deployed()
        .then(_thriftInstance => {
            thriftInstance = _thriftInstance;
            return thriftInstance.createThrift(maxParticipants, roundAmount, roundPeriodHrs, {value: 100})
        })
        .then(() => {
            return thriftInstance.thrifts(0)
        })
        .then(createdThrift => {
            assert.equal(createdThrift.id, 0, "created thrift with the wrong id");
            assert.equal(createdThrift.maxParticipants, maxParticipants, "wrong thrift participants number");
            assert.equal(createdThrift.roundAmount, roundAmount, "wrong thrift round amount");
            assert.equal(createdThrift.roundPeriod, roundPeriodSecs, "wrong thrift round period set")
            assert.equal(createdThrift.minStake, minStake, "wrong minStake amount set");
        })
    });

    it("should allow new participants be able to join thrift and start when participant completion", () => {
        let thriftInstance;

        const maxParticipants = 2;
        const roundAmount = 50;
        const roundPeriodHrs = 1;
        // const minStake = maxParticipants * roundAmount;

        return ThriftManager.deployed()
        .then(_thriftInstance => {
            thriftInstance = _thriftInstance;
            return thriftInstance.createThrift(maxParticipants, roundAmount, roundPeriodHrs, {value: 100});
        })
        .then(async () => {
            const id = 0;
            await thriftInstance.joinThrift(id, {from: accounts[1], value: 100})
            return thriftInstance.thrifts(id);
        })
        .then(_thrift => {
            assert.equal(_thrift.numParticipants.toNumber(), 2, "number of participants mismatch");
            assert.equal(_thrift.start, true, "thrift not started on partcicipants completion");
        })
    });

    it("should close thrift at end of contribution", () => {
        let thriftInstance;

        const maxParticipants = 2;
        const roundAmount = 50;
        const roundPeriodHrs = 1;

        return ThriftManager.deployed()
        .then(_thriftInstance => {
            thriftInstance = _thriftInstance;
            return thriftInstance.createThrift(maxParticipants, roundAmount, roundPeriodHrs, {value: 100});
        })
        .then(async () => {
            const id = 1;
            await thriftInstance.joinThrift(id, {from: accounts[1], value: 100})
            return thriftInstance.thrifts(id);
        })
        .then(async () => {
            const id = 1;
            // 1st round contribution
            await thriftInstance.contributeToThrift(id, {value: roundAmount});
            await thriftInstance.contributeToThrift(id, {value: roundAmount, from: accounts[1]});
            // 2nd round contribution
            await thriftInstance.contributeToThrift(id, {value: roundAmount});
            await thriftInstance.contributeToThrift(id, {value: roundAmount, from: accounts[1]});
            return thriftInstance.thrifts(1);
        })
        .then(_thrift => {
            assert.equal(_thrift.completed, true, "thrift dosent complete at end of contribution");
        })
    });

    it("closes thrift with correct balances and payout", async () => {
        let thriftInstance;

        const maxParticipants = 2;
        const roundAmount = 50;
        const roundPeriodHrs = 1;

        const [_, contrib_two] = accounts;

        return ThriftManager.deployed()
        .then(async _thriftInstance => {
            thriftInstance = _thriftInstance;
            await thriftInstance.createThrift(maxParticipants, roundAmount, roundPeriodHrs, {value: 100});
            // console.log("After thrift creation");
            const thriftBal = (await thriftInstance.thrifts(2)).balance.toString();
            assert.equal(thriftBal, "100", "thrift initialized with incorrect balance");
        })
        .then(async () => {
            await thriftInstance.joinThrift(2, {value: 100, from: contrib_two});
            const thriftBal = (await thriftInstance.thrifts(2)).balance. toString();
            assert.equal(thriftBal, "200", "joining thrift dosent update balance");
        })  
        .then(async () => {
            const id = 2;
            // 1st round contribution
            await thriftInstance.contributeToThrift(id, {value: roundAmount});
            await thriftInstance.contributeToThrift(id, {value: roundAmount, from: accounts[1]});
            let thriftBal = (await thriftInstance.thrifts(2)).balance.toString();
            assert.equal(thriftBal, "200", "thrift dosent update balance at end on contribution round");
            // 2nd round and finnal contribution
            await thriftInstance.contributeToThrift(id, {value: roundAmount});
            await thriftInstance.contributeToThrift(id, {value: roundAmount, from: accounts[1]});
            thriftBal = (await thriftInstance.thrifts(2)).balance.toString();
            assert.equal(thriftBal, "0", "thrift balance should be zero at end on thrift");
        })
    })
})