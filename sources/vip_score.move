/// vip_score is the contract to provide a score for each contracts.
module vip_score::vip_score {
    use std::vector;
    use std::event;
    use std::option::{Self, Option};

    use minitia_std::signer;
    use minitia_std::table;
    use minitia_std::error;
    use minitia_std::simple_map::{Self, SimpleMap};

    struct ModuleStore has key {
        init_stage: u64,
        deployers: SimpleMap<address, bool>,
        scores: table::Table<u64 /* stage */, Scores>
    }

    struct Scores has store {
        total_score: u64,
        is_finalized: bool,
        score: table::Table<address /* user */, u64>
    }

    //
    // Constants
    //

    const MAX_LIMIT: u16 = 1000;

    //
    // Errors
    //

    /// The permission is denied.
    const EUNAUTHORIZED: u64 = 1;

    /// Insufficient score to decrease.
    const EINSUFFICIENT_SCORE: u64 = 2;

    /// The stage is not initialized.
    const EINVALID_STAGE: u64 = 3;

    /// The deployer is already added.
    const EDEPLOYER_ALREADY_ADDED: u64 = 4;

    /// The deployer is not found.
    const EDEPLOYER_NOT_FOUND: u64 = 5;

    /// The length of addrs and scores is not matched.
    const ENOT_MATCH_LENGTH: u64 = 6;

    /// The score is invalid.
    const EINVALID_SCORE: u64 = 7;

    /// The stage is already finalized.
    const EFINALIZED_STAGE: u64 = 8;

    // The previous stage is not finalized.
    const EPREVIOUS_STAGE_NOT_FINALIZED: u64 = 9;

    // Can not set initial stage to 0;
    const ESTAGE_ZERO: u64 = 10;

    // Already called set_init_stage;
    const EALREADY_SET: u64 = 11;
    //
    // Events
    //

    #[event]
    struct DeployerAddedEvent has drop, store {
        deployer: address
    }

    #[event]
    struct DeployerRemovedEvent has drop, store {
        deployer: address
    }

    #[event]
    struct UpdateScoreEvent has drop, store {
        account: address,
        stage: u64,
        score: u64,
        total_score: u64
    }

    #[event]
    struct FinalizedScoreEvent has drop, store {
        stage: u64
    }

    //
    // Implementation
    //

    fun init_module(publisher: &signer) {
        move_to(
            publisher,
            ModuleStore {
                init_stage: 0,
                deployers: simple_map::create<address, bool>(),
                scores: table::new<u64, Scores>()
            }
        );
    }

    public entry fun set_init_stage(deployer: &signer, stage: u64) acquires ModuleStore {
        assert!(stage != 0, error::invalid_argument(ESTAGE_ZERO));
        check_deployer_permission(deployer);
        let module_store = borrow_global_mut<ModuleStore>(@vip_score);
        assert!(module_store.init_stage == 0, error::already_exists(EALREADY_SET));
        module_store.init_stage = stage;
        create_stage(stage);
    }

    /// Check signer's permisson
    fun check_permission(publisher: &signer) {
        assert!(
            signer::address_of(publisher) == @vip_score,
            error::permission_denied(EUNAUTHORIZED)
        );
    }

    fun check_deployer_permission(deployer: &signer) acquires ModuleStore {
        let module_store = borrow_global_mut<ModuleStore>(@vip_score);
        let found =
            simple_map::contains_key(
                &module_store.deployers,
                &signer::address_of(deployer)
            );
        assert!(found, error::invalid_argument(EUNAUTHORIZED));
    }

    fun update_score_internal(
        scores: &mut Scores,
        account: address,
        stage: u64,
        amount: u64
    ) {

        let score = table::borrow_mut_with_default(&mut scores.score, account, 0);

        scores.total_score = scores.total_score - *score + amount;
        *score = amount;

        event::emit(
            UpdateScoreEvent {
                account: account,
                stage: stage,
                score: *score,
                total_score: scores.total_score
            }
        )
    }
    //
    // View functions
    //

    struct GetScoresResponse {
        stage: u64,
        scores: vector<Score>
    }

    struct Score {
        addr: address,
        score: u64
    }

    #[view]
    public fun get_scores(
        // The stage number
        stage: u64,
        // Number of results to return (Max: 1000)
        limit: u16,
        // Pagination key. If None, start from the beginning.
        // If provided, return results after this key in descending order.
        // Use the last returned address to fetch the next page.
        start_after: Option<address>
    ): GetScoresResponse acquires ModuleStore {
        let module_store = borrow_global<ModuleStore>(@vip_score);
        let scores: vector<Score> = vector[];

        // check stage exists
        if (!table::contains(&module_store.scores, stage)) {
            return GetScoresResponse { stage, scores }
        };

        // check max limit
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT
        };

        // collect scores
        let score = table::borrow(&module_store.scores, stage);
        let iter = table::iter(
            &score.score,
            option::none(),
            start_after, // exclusive
            2
        );

        while (table::prepare<address, u64>(iter)
            && vector::length(&scores) < (limit as u64)) {
            let (addr, score) = table::next<address, u64>(iter);

            vector::push_back(&mut scores, Score { addr, score: *score });
        };

        return GetScoresResponse { stage, scores }
    }

    #[view]
    public fun get_score(account: address, stage: u64): u64 acquires ModuleStore {
        let module_store = borrow_global<ModuleStore>(@vip_score);
        if (!table::contains(&module_store.scores, stage)) {
            return 0
        };
        let scores = table::borrow(&module_store.scores, stage);
        *table::borrow_with_default(&scores.score, account, &0)
    }

    #[view]
    public fun get_total_score(stage: u64): u64 acquires ModuleStore {
        let module_store = borrow_global<ModuleStore>(@vip_score);
        if (!table::contains(&module_store.scores, stage)) {
            return 0
        };
        let scores = table::borrow(&module_store.scores, stage);
        scores.total_score
    }

    //
    // Public functions
    //
    // Check deployer permission and create a stage score table if not exists.
    fun create_stage(stage: u64) acquires ModuleStore {
        let module_store = borrow_global_mut<ModuleStore>(@vip_score);
    
        table::add(
            &mut module_store.scores,
            stage,
            Scores {
                total_score: 0,
                is_finalized: false,
                score: table::new<address, u64>()
            }
        );
    }

    /// Increase a score of an account.
    public fun increase_score(
        deployer: &signer,
        account: address,
        stage: u64,
        amount: u64
    ) acquires ModuleStore {
        check_deployer_permission(deployer);

        let module_store = borrow_global_mut<ModuleStore>(@vip_score);

        assert!(
            table::contains(&module_store.scores, stage),
            error::invalid_argument(EINVALID_STAGE)
        );

        let scores = table::borrow_mut(&mut module_store.scores, stage);
        assert!(
            !scores.is_finalized,
            error::invalid_argument(EFINALIZED_STAGE)
        );

        let score = table::borrow_mut_with_default(&mut scores.score, account, 0);

        *score = *score + amount;
        scores.total_score = scores.total_score + amount;

        event::emit(
            UpdateScoreEvent {
                account: account,
                stage: stage,
                score: *score,
                total_score: scores.total_score
            }
        )
    }

    /// Decrease a score of an account.
    public fun decrease_score(
        deployer: &signer,
        account: address,
        stage: u64,
        amount: u64
    ) acquires ModuleStore {
        check_deployer_permission(deployer);

        let module_store = borrow_global_mut<ModuleStore>(@vip_score);

        assert!(
            table::contains(&module_store.scores, stage),
            error::invalid_argument(EINVALID_STAGE)
        );

        let scores = table::borrow_mut(&mut module_store.scores, stage);
        assert!(
            !scores.is_finalized,
            error::invalid_argument(EFINALIZED_STAGE)
        );

        let score = table::borrow_mut(&mut scores.score, account);
        assert!(
            *score >= amount,
            error::invalid_argument(EINSUFFICIENT_SCORE)
        );
        *score = *score - amount;
        scores.total_score = scores.total_score - amount;

        event::emit(
            UpdateScoreEvent {
                account: account,
                stage: stage,
                score: *score,
                total_score: scores.total_score
            }
        )
    }

    public fun update_score(
        deployer: &signer,
        account: address,
        stage: u64,
        amount: u64
    ) acquires ModuleStore {
        check_deployer_permission(deployer);
        assert!(
            amount >= 0,
            error::invalid_argument(EINVALID_SCORE)
        );

        let module_store = borrow_global_mut<ModuleStore>(@vip_score);
        assert!(
            table::contains(&module_store.scores, stage),
            error::invalid_argument(EINVALID_STAGE)
        );

        let scores = table::borrow_mut(&mut module_store.scores, stage);
        assert!(
            !scores.is_finalized,
            error::invalid_argument(EFINALIZED_STAGE)
        );

        update_score_internal(scores, account, stage, amount);
    }

    //
    // Entry functions
    //
    public entry fun finalize_script(deployer: &signer, stage: u64) acquires ModuleStore {
        check_deployer_permission(deployer);
        let module_store = borrow_global_mut<ModuleStore>(@vip_score);

        assert!(
            table::contains(&module_store.scores, stage),
            error::invalid_argument(EINVALID_STAGE)
        );

        let scores = table::borrow_mut(&mut module_store.scores, stage);
        assert!(
            !scores.is_finalized,
            error::invalid_argument(EFINALIZED_STAGE)
        );
        scores.is_finalized = true;

        create_stage(stage + 1);

        event::emit(FinalizedScoreEvent { stage })

    }

    public entry fun update_score_script(
        deployer: &signer,
        stage: u64,
        addrs: vector<address>,
        update_scores: vector<u64>
    ) acquires ModuleStore {
        check_deployer_permission(deployer);
        assert!(
            vector::length(&addrs) == vector::length(&update_scores),
            error::invalid_argument(ENOT_MATCH_LENGTH)
        );

        let module_store = borrow_global_mut<ModuleStore>(@vip_score);
        assert!(
            table::contains(&module_store.scores, stage),
            error::invalid_argument(EINVALID_STAGE)
        );

        let scores = table::borrow_mut(&mut module_store.scores, stage);
        assert!(
            !scores.is_finalized,
            error::invalid_argument(EFINALIZED_STAGE)
        );
        vector::enumerate_ref(
            &addrs,
            |i, addr| {
                update_score_internal(
                    scores,
                    *addr,
                    stage,
                    *vector::borrow(&update_scores, i)
                );
            }
        );
    }

    public entry fun add_deployer_script(
        publisher: &signer, deployer: address
    ) acquires ModuleStore {
        check_permission(publisher);
        let module_store = borrow_global_mut<ModuleStore>(@vip_score);
        assert!(
            !simple_map::contains_key(&module_store.deployers, &deployer),
            error::invalid_argument(EDEPLOYER_ALREADY_ADDED)
        );
        simple_map::add(&mut module_store.deployers, deployer, true);

        event::emit(DeployerAddedEvent { deployer: deployer })
    }

    public entry fun remove_deployer_script(
        publisher: &signer, deployer: address
    ) acquires ModuleStore {
        check_permission(publisher);
        let module_store = borrow_global_mut<ModuleStore>(@vip_score);
        assert!(
            simple_map::contains_key(&module_store.deployers, &deployer),
            error::invalid_argument(EDEPLOYER_NOT_FOUND)
        );
        simple_map::remove(&mut module_store.deployers, &deployer);

        event::emit(DeployerRemovedEvent { deployer: deployer })
    }

    //
    // Tests
    //

    #[test_only]
    public fun init_module_for_test() {
        init_module(&minitia_std::account::create_signer_for_test(@vip_score));
    }

    #[test(publisher = @0x2, deployer = @0x2, user = @0x123)]
    #[expected_failure(abort_code = 0x10001, location = Self)]
    fun failed_remove_deployer_script(
        publisher: &signer, deployer: &signer, user: address
    ) acquires ModuleStore {
        init_module_for_test();

        add_deployer_script(publisher, signer::address_of(deployer));
        set_init_stage(deployer, 1);
        increase_score(deployer, user, 1, 100);
        assert!(get_score(user, 1) == 100, 1);
        remove_deployer_script(publisher, signer::address_of(deployer));
        increase_score(deployer, user, 1, 100);
    }

    #[test(publisher = @0x2, deployer = @0x2, user = @0x123)]
    #[expected_failure(abort_code = 0x10002, location = Self)]
    fun failed_decrease_score_isufficient(
        publisher: &signer, deployer: &signer, user: address
    ) acquires ModuleStore {
        init_module_for_test();
        add_deployer_script(publisher, signer::address_of(deployer));
        set_init_stage(deployer, 1);
        increase_score(deployer, user, 1, 100);
        assert!(get_score(user, 1) == 100, 1);
        decrease_score(deployer, user, 1, 10000);
    }

    #[test(publisher = @0x2, deployer = @0x2)]
    #[expected_failure(abort_code = 0x10004, location = Self)]
    fun failed_add_deployer_script_already_exist(
        publisher: &signer, deployer: &signer
    ) acquires ModuleStore {
        init_module_for_test();
        add_deployer_script(publisher, signer::address_of(deployer));
        add_deployer_script(publisher, signer::address_of(deployer));
    }

    #[test(publisher = @0x2, deployer = @0x2)]
    #[expected_failure(abort_code = 0x10005, location = Self)]
    fun failed_remove_deployer_script_not_found(
        publisher: &signer, deployer: &signer
    ) acquires ModuleStore {
        init_module_for_test();
        remove_deployer_script(publisher, signer::address_of(deployer));
    }

    #[test(publisher = @0x2, deployer = @0x2)]
    #[expected_failure(abort_code = 0x10006, location = Self)]
    fun failed_not_match_length(publisher: &signer, deployer: &signer) acquires ModuleStore {
        init_module_for_test();
        add_deployer_script(publisher, signer::address_of(deployer));
        set_init_stage(deployer, 1);
        update_score_script(deployer, 1, vector[@0x123, @0x234], vector[]);
    }

    #[test(publisher = @0x2, deployer = @0x2, user = @0x123)]
    #[expected_failure(abort_code = 0x10008, location = Self)]
    fun failed_finalized_stage(
        publisher: &signer, deployer: &signer, user: address
    ) acquires ModuleStore {
        init_module_for_test();
        add_deployer_script(publisher, signer::address_of(deployer));
        set_init_stage(deployer, 1);
        increase_score(deployer, user, 1, 100);
        assert!(get_score(user, 1) == 100, 1);
        finalize_script(deployer, 1);
        increase_score(deployer, user, 1, 100);
    }

    #[
        test(
            publisher = @0x2,
            deployer_a = @0x2,
            deployer_b = @0x3,
            user_a = @0x123,
            user_b = @0x456
        )
    ]
    fun test_e2e(
        publisher: &signer,
        deployer_a: &signer,
        deployer_b: &signer,
        user_a: address,
        user_b: address
    ) acquires ModuleStore {
        init_module_for_test();

        add_deployer_script(publisher, signer::address_of(deployer_a));
        add_deployer_script(publisher, signer::address_of(deployer_b));
        set_init_stage(deployer_a, 1);
        // increase score by deployer_a
        increase_score(deployer_a, user_a, 1, 100);
        increase_score(deployer_a, user_b, 1, 50);
        assert!(get_score(user_a, 1) == 100, 1);
        assert!(get_score(user_b, 1) == 50, 2);

        // increase score by deployer_b
        increase_score(deployer_b, user_a, 1, 100);
        increase_score(deployer_b, user_b, 1, 50);
        assert!(get_score(user_a, 1) == 200, 3);
        assert!(get_score(user_b, 1) == 100, 4);
        assert!(get_total_score(1) == 300, 5);

        // decrease score of user_a
        decrease_score(deployer_a, user_a, 1, 50);
        decrease_score(deployer_b, user_b, 1, 50);
        assert!(get_score(user_a, 1) == 150, 6);
        assert!(get_score(user_b, 1) == 50, 7);
        assert!(get_total_score(1) == 200, 8);

        update_score(deployer_a, user_a, 1, 300);
        update_score(deployer_b, user_b, 1, 300);
        assert!(get_score(user_a, 1) == 300, 9);
        assert!(get_score(user_b, 1) == 300, 10);
        assert!(get_total_score(1) == 600, 11);
        // finalize stage
        finalize_script(deployer_a, 1);
        // automatically prepare stage
        update_score_script(
            deployer_a,
            2,
            vector[user_a, user_b],
            vector[100, 200]
        );

        assert!(get_score(user_a, 2) == 100, 12);
        assert!(get_score(user_b, 2) == 200, 13);
        assert!(get_total_score(2) == 300, 14);
    }

    #[test(publisher = @0x2, deployer = @0x2)]
    fun test_update_score_script(publisher: &signer, deployer: &signer) acquires ModuleStore {
        init_module_for_test();
        let stage = 1;
        add_deployer_script(publisher, signer::address_of(deployer));
        set_init_stage(deployer, 1);
        let scores = vector::empty<u64>();
        let addrs = vector::empty<address>();
        let idx = 0;
        while (idx < 50000) {
            vector::push_back(&mut scores, 100);
            vector::push_back(&mut addrs, @0x123);
            idx = idx + 1;
        };
        update_score_script(deployer, stage, addrs, scores);
        finalize_script(deployer, stage);
        let next_stage = 2;
        update_score_script(deployer, next_stage, addrs, scores);

    }

    #[test(deployer = @0x2, non_deployer = @0x3)]
    #[expected_failure(abort_code = 0x10001, location = Self)]
    fun failed_update_score_script_by_non_deployer(
        deployer: &signer, non_deployer: &signer
    ) acquires ModuleStore {
        init_module_for_test();
        let stage = 1;
        set_init_stage(deployer, stage);
        let scores = vector::empty<u64>();
        let addrs = vector::empty<address>();
        let idx = 0;
        while (idx < 50000) {
            vector::push_back(&mut scores, 100);
            vector::push_back(&mut addrs, @0x123);
            idx = idx + 1;
        };
        update_score_script(non_deployer, stage, addrs, scores)
    }

    #[test(publisher = @0x2, deployer = @0x2)]
    #[expected_failure(abort_code = 0x10003, location = Self)]
    fun failed_finalize_script_by_skip_finalize_previous_stage(
        publisher: &signer, deployer: &signer
    ) acquires ModuleStore {
        init_module_for_test();
        let init_stage = 5;
        let scores = vector::empty<u64>();
        let addrs = vector::empty<address>();
        add_deployer_script(publisher, signer::address_of(deployer));
        vector::push_back(&mut scores, 100);
        vector::push_back(&mut addrs, @0x123);

        set_init_stage(deployer, init_stage);

        // skip stages

        let next_stage = 10;
        update_score_script(deployer, next_stage, addrs, scores);
        finalize_script(deployer, next_stage);
    }

    #[test(publisher = @0x2, deployer = @0x2)]
    fun test_init_stage_3_and_update_score_script(
        publisher: &signer, deployer: &signer
    ) acquires ModuleStore {
        init_module_for_test();
        let init_stage = 3;
        let scores = vector::empty<u64>();
        let addrs = vector::empty<address>();
        add_deployer_script(publisher, signer::address_of(deployer));
        set_init_stage(deployer, init_stage);
        vector::push_back(&mut scores, 100);
        vector::push_back(&mut addrs, @0x123);

        update_score_script(deployer, init_stage, addrs, scores);
        finalize_script(deployer, init_stage);
        let next_stage = 4;
        update_score_script(deployer, next_stage, addrs, scores);

    }
}
