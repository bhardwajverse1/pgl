open Basics;;
open Paritygame;;
open Univsolve;;
open Transformations;;
open Tcsset;;
open Tcsarray;;
open Tcslist;;
open Tcsstrings;;
open Tcsbasedata;;
open Tcsgraph;;
open Tcsmaths;;
open Arg;;
open Tcsargs;;
open Pgnodeset;;
open Pgplayer;;
open Pgpriority;;
open Pgsolution;;
open Pgstrategy;;
open Pgnode;;
open Arrayparitygame;;

(* let array_max a less = ArrayUtils.max_elt (fun x y -> if less x y then -1 else 1) a *)
let list_max a less = ListUtils.max_elt (fun x y -> if less x y then -1 else 1) a


let enable_exp_bit_count = ref false

let last_exp_bit_count = ref 0

let get_last_exp_bit_count _ = !last_exp_bit_count

let last_iteration_count = ref 0

let get_last_iteration_count _ = !last_iteration_count

let _strat_impr_callback = ref None


type node_valuation = int * int TreeSet.t * int

type game_valuation = node_valuation array

type initial_strategy_fun = paritygame -> strategy

type node_total_ordering_fun = paritygame -> int -> int -> int

type 'a improvement_policy_fun = paritygame -> node_total_ordering_fun -> 'a -> strategy -> game_valuation -> strategy * 'a

let format_node_valuation (a, b, c) =
    let t = TreeSet.fold (fun el s -> s ^ (string_of_int el) ^", ") b "" in
    (string_of_int a) ^ " [" ^ t ^ "] " ^ (string_of_int c)

let format_game_valuation valu =
    let s = ref "" in
    for i = 0 to Array.length valu - 1 do
        s := !s ^ format_node_valuation valu.(i) ^ "\n"
    done;
    !s

let flip f x y = f y x

let tuple_total_ordering cmp f (x, r) (y, s) =
	let c = cmp x y in
	if c = 0 then f r s else c

let node_total_ordering_by_position _ i j =
	compare i j

let node_total_ordering_by_priority_and_position game i j =
	tuple_total_ordering compare compare (game#get_priority  i, i) (game#get_priority  j, j)

let relevance_total_ordering game node_total_ordering i j =
	tuple_total_ordering compare (node_total_ordering game) (game#get_priority  i, i) (game#get_priority  j, j)

let reward_total_ordering game node_total_ordering i j =
	let ri = reward plr_Even (game#get_priority  i) in
	let rj = reward plr_Even (game#get_priority  j) in
	let c = compare ri rj in
	if c != 0 then c
	else node_total_ordering game (if ri mod 2 = 0 then i else j) (if ri mod 2 = 0 then j else i)

let initial_strategy_by_what game selector =
	str_init game (fun i ->
				   let tr = game#get_successors  i in
				   if not (game#is_defined  i) || (game#get_owner  i = plr_Odd) || (ns_isEmpty tr) then nd_undef else selector tr
	)

let initial_strategy_by_first_edge game = initial_strategy_by_what game ns_first
let initial_strategy_by_last_edge game = initial_strategy_by_what game ns_last
let initial_strategy_by_random_edge game = initial_strategy_by_what game ns_random
let initial_strategy_by_best_reward game =
  initial_strategy_by_what game
			   (fun tr -> ns_max tr (fun i j -> reward_total_ordering game node_total_ordering_by_position i j <= 0))

let empty_descending_relevance_ordered_set game node_total_ordering =
	TreeSet.empty (flip (relevance_total_ordering game node_total_ordering))

let node_valuation_ordering game node_total_ordering (u, p, e) (v, q, f) =
    let is_odd x = game#get_priority  x mod 2 = 1 in
    let is_even x = game#get_priority  x mod 2 = 0 in
	let cycle_ordering = reward_total_ordering game node_total_ordering in
	let length_ordering (u, e) (v, f) =
		if e = f then 0
		else if ((is_odd v) && e < f) || ((is_even v) && e > f) then -1 else 1 in
	let path_ordering p q =
		let r = TreeSet.sym_diff p q in
		if TreeSet.cardinal r = 0 then 0
		else let w = TreeSet.min_elt r in
		     if ((is_even w) && TreeSet.mem w q) || ((is_odd w) && TreeSet.mem w p) then -1 else 1
    in
    tuple_total_ordering cycle_ordering
    	                 (tuple_total_ordering path_ordering length_ordering)
    	                 (u, (p, (u, e))) (v, (q, (v, f)))

let node_valuation_total_ordering game node_total_ordering valu x y =
	tuple_total_ordering (node_valuation_ordering game node_total_ordering)
						 (node_total_ordering game)
						 (valu.(x), x) (valu.(y), y)

let best_decision_by_ordering game ordering v =
	let ordering x y = ordering x y >= 0 in
	let pl = game#get_owner  v in
	let tr = game#get_successors  v in
	ns_max tr (fun x y -> if pl = plr_Odd then ordering x y else ordering y x)

let best_decision_by_valuation_ordering game node_total_ordering valu v =
	best_decision_by_ordering game (node_valuation_total_ordering game node_total_ordering valu) v

let strategy_improvable game node_total_ordering strat valu =
    strat#exists (fun i j ->
        (game#get_owner  i = plr_Even) &&
        (node_valuation_ordering game node_total_ordering valu.(j)
        						 valu.(best_decision_by_valuation_ordering game node_total_ordering valu i) < 0)
    )

let winning_regions game valu =
    sol_init game (fun i ->
        let (v, _, _) = valu.(i) in
        plr_benefits (game#get_priority  v)
    )

let winning_strategies game node_total_ordering strat valu =
    str_init game (fun i ->
        let (v, _, _) = valu.(i) in
        let winner = plr_benefits (game#get_priority  v) in
        let player = game#get_owner  i in
        if winner = player
        then if player = plr_Even then strat#get i
             else best_decision_by_valuation_ordering game node_total_ordering valu i
        else nd_undef
    )

let evaluate_strategy game node_total_ordering strat =
	let n = game#size  in
	let graph = game#to_dynamic_paritygame_by_strategy strat in
	let asc_rew = DynamicGraph.add_cmp (reward_total_ordering game node_total_ordering) graph in
	let rel_ord = relevance_total_ordering game node_total_ordering in
	let des_rel = DynamicGraph.add_cmp (flip rel_ord) graph in
	let valu = Array.make n (-1, empty_descending_relevance_ordered_set game node_total_ordering, 0) in

	DynamicGraph.iter_by (fun v ->
		let (w, _, _) = valu.(v) in
		if (w = -1) && (DynamicGraph.depth_find v (fun u -> rel_ord u v <= 0)
		                                          (fun u -> DynamicGraph.has_edge u v graph)
		                                          graph) then (
			let graph' = DynamicGraph.sub_graph_by_node_closure v (fun u f -> TreeSet.iter f (DynamicGraph.get_node_pred u graph)) graph in
			let del_other_edges x m =
				TreeSet.iter (fun y ->
					if not (TreeSet.mem y m) then DynamicGraph.del_edge x y graph'
				) (DynamicGraph.get_node_succ x graph')
			in
			DynamicGraph.iter (fun u _ -> valu.(u) <- (v, empty_descending_relevance_ordered_set game node_total_ordering, 0)) graph';
			DynamicGraph.iter_by (fun u ->
				if rel_ord u v > 0 then (
					if game#get_priority  u mod 2 = 0 then (
						let m = GraphUtils.build_reachability_set (v, (fun x -> TreeSet.to_iterator (TreeSet.filter ((!=) u) (DynamicGraph.get_node_pred x graph')))) in
						DynamicGraph.iter (fun q _ ->
							if not (TreeSet.mem q m)
							then let (a, b, c) = valu.(q) in
								 valu.(q) <- (a, TreeSet.add u b, c)
						) graph';
						del_other_edges u m;
						TreeSet.iter (fun q -> del_other_edges q m) m
					)
					else (
						let m = GraphUtils.build_reachability_set (u, (fun x -> TreeSet.to_iterator (TreeSet.filter ((!=) v) (DynamicGraph.get_node_pred x graph')))) in
						TreeSet.iter (fun q ->
							let (a, b, c) = valu.(q) in
							valu.(q) <- (a, TreeSet.add u b, c)
						) m;
						TreeSet.iter (fun x ->
							if not (x = u) then del_other_edges x m
						) m
					)
				)
			) des_rel graph';
			let f n i = let (p0, p1, _) = valu.(n) in valu.(n) <- (p0, p1, i) in
			if game#get_priority  v mod 2 = 0
            then GraphUtils.iterate_with_maximal_distance_single_loop (v, (fun x -> TreeSet.to_iterator (DynamicGraph.get_node_pred x graph')),
                                                                       (fun x -> TreeSet.to_iterator (DynamicGraph.get_node_succ x graph'))) f
            else GraphUtils.iterate_with_minimal_distance (v, (fun x -> TreeSet.to_iterator (DynamicGraph.get_node_pred x graph'))) f;
			DynamicGraph.iter (fun u _ -> DynamicGraph.del_node u graph) graph'
		)
	) asc_rew graph;
	valu

let counter_strategy_by_valu_and_ordering game valu ordering =
    str_init game (fun i ->
		if game#get_owner i = plr_Even
		then nd_undef
		else best_decision_by_valuation_ordering game ordering valu i
    )

let compute_counter_strategy game strategy =
    counter_strategy_by_valu_and_ordering game (evaluate_strategy game node_total_ordering_by_position strategy) node_total_ordering_by_position

let less_valuation val_comp v u =
	let res = ref false in
	let fin = ref false in
	let n = Array.length v in
	let i = ref 0 in
	while (!i < n) && (not !fin) do
		let c = val_comp v.(!i) u.(!i) in
		if c > 0 then (
			res := false;
			fin := true
		)
		else if c < 0 then (
			res := true
		);
		incr i
	done;
	!res

(* TEST *)
(*
let format_game_state game valu =

    let lookup_node s =
        let check i =
            match (game#get_desc  i) with
                None -> false
            |   Some t -> s=t
        in
        let i = ref 0 in
        let n = Array.length game in
        while (!i < n) && (not (check !i)) do
            incr i
        done;
        if !i < n then Some !i else None
    in

    let l = ref [] in
    let i = ref (-1) in
    let go = ref true in

   *)
let format_game_state game valu =

    let lookup_node s =
        let check i =
            match (game#get_desc  i) with
                None -> false
            |   Some t -> s=t
        in
        let i = ref 0 in
        let n = game#size  in
        while (!i < n) && (not (check !i)) do
            incr i
        done;
        if !i < n then Some !i else None
    in

    let l = ref [] in
    let i = ref (-1) in
    let go = ref true in

	if lookup_node "e0" = None then (
	    let u0 = lookup_node "k0" in
	    match u0 with
	    	Some d -> (
			    let (_, vald, _) = valu.(d) in
			    while !go do
			    	incr i;
			    	match (lookup_node ("k" ^ string_of_int !i)) with
			    		Some e -> (
			    			l := (if TreeSet.mem e vald then 1 else 0)::!l
			    		)
			    	|	None -> go := false
			    done
			   )
		|	_ -> ()
	)
	else (
	    while !go do
	    	incr i;
	    	match (lookup_node ("e" ^ string_of_int !i)) with
	    		Some e -> (
	    			match (lookup_node ("d(0,0,0)")) with
	    				Some _ -> (
		                let go2 = ref true in
		                let j = ref 0 in
		                let k = ref (-1) in
		                let pass = ref true in
		                while !go2 && !pass do
		                    incr k;
		                    match (lookup_node ("d(" ^ string_of_int !i ^ ","^string_of_int !j^","^string_of_int !k^ ")")) with
		                    	Some d -> (
		                    		let (_, vald, _) = valu.(d) in
		                    		pass := TreeSet.mem e vald;
		                    		go2 := !pass
		                    	)
		                    |	_ -> (
		                    	if !k = 0 then go2 := false else (k := -1; incr j)
		                    )
		                done;
		            	l := (if !pass then 1 else 0)::!l
	    				)
	    			|	None -> (
						match (lookup_node "d0") with
							Some _ -> (
								let pass = ref false in
								(
								match (lookup_node ("d" ^ string_of_int !i)) with
									Some d -> (
										let (_, vald, _) = valu.(d) in
										pass := TreeSet.mem e vald;
									)
								|	_ -> ();
								);
								l := (if !pass then 1 else 0)::!l
							)
						|	None -> (
		                let go2 = ref true in
		                let j = ref (-1) in
		                let pass = ref true in
		                while !go2 && !pass do
		                    incr j;
		                    match (lookup_node ("d(" ^ string_of_int !i ^ ","^string_of_int !j^ ")")) with
		                    	Some d -> (
		                    		let (_, vald, _) = valu.(d) in
		                    		pass := TreeSet.mem e vald;
		                    		go2 := !pass
		                    	)
		                    |	_ -> go2 := false
		                done;
		            	l := (if !pass then 1 else 0)::!l
		            ))
	    		)
	    	|	_ -> go := false
	    done
	);

(*
    let l' = ref [] in
    let i = ref (-1) in
    let go = ref true in

    while !go do
    	incr i;
    	match (lookup_node ("e" ^ string_of_int !i), lookup_node ("h" ^ string_of_int !i)) with
    		(Some e, Some h) -> (
    			let (_, vale, _) = valu.(e) in
	    		l' := (if TreeSet.mem h vale then 1 else 0)::!l'
    		)
    	|	_ -> go := false;
    done;

    let upl = ref [] in
    let i = ref (-1) in
    let go = ref true in

    while !go do
    	incr i;
    	match (lookup_node ("k" ^ string_of_int !i)) with
    		Some k -> (
    			let (_, valk, _) = valu.(k) in
    			let x = ref (0) in
    			let j = ref !i in
    			let go2 = ref true in
    			while !go2 do
    				incr j;
    				match (lookup_node ("f" ^ string_of_int !j)) with
    					Some f -> (
    						if TreeSet.mem f valk then (
    							x := !j;
    							go2 := false
    						)
    					)
    				| _ -> go2 := false
    			done;
    			upl := (!i, !x)::!upl
    		)
    	|	_ -> go := false
    done;
*)
     let v = ref 0 in

    let u = List.map (fun b ->
    	v := 2 * !v;
    	if b=1 then incr v;
    	if b=1 then "1" else "0"
    ) !l in
(*
    let w = List.map (fun (_, h) ->
    	string_of_int h
    ) !upl in

    let l = ref [] in
    let i = ref (-1) in
    let go = ref true in
    while !go do
    	incr i;
    	match (lookup_node ("f" ^ string_of_int !i)) with
    		Some f -> l := (!i, f)::!l
    	|	None -> go := false
    done;

    let cmp = (fun (_, f) (_, f') -> (node_valuation_ordering game (node_total_ordering_by_position) valu.(f') valu.(f))) in
    let a = Array.of_list !l in
    Array.sort cmp a;
    let s = ListUtils.format (fun (i, _) -> string_of_int i) (Array.to_list a) in

    let s' = ListUtils.format string_of_int !l' in

    (("[" ^ String.concat "," u ^ "]" ^ " / [" ^ String.concat "," w ^ "]" ^ " / " ^ s ^ " / " ^ s'), !v)
*)
    (("[" ^ String.concat "," u ^ "]"), !v)


let transform_game_state_list l =
	let t = ref [] in
	let l = ref l in
	let v = ref (-1) in
	while !l != [] do
		let (s, v') = List.hd !l in
		l := List.tl !l;
		if (!v < 0) || (v' < !v) then (
			v := v';
			t := (s, v')::!t
		)
	done;
	!t


(* TEST *)


let strategy_improvement (game: paritygame)
						 (init_strat: initial_strategy_fun)
						 (node_compare: node_total_ordering_fun)
						 (impr_policy: 'a improvement_policy_fun)
						 (impr_policy_init: 'a)
						 (check_policy: bool)
						 (ident: string) =

    let msg_tagged v = message_autotagged v (fun _ -> ident) in
    let msg_tagged_nl v = message_autotagged_newline v (fun _ -> ident) in
    let msg_plain = message in

    msg_tagged 2 (fun _ -> "Starting strategy improvement algorithm\n");
    if !verbosity > 2 then (
	    msg_tagged_nl 3 (fun _ -> "Considering game:\n" ^ game#to_string ^ "\n")
	);

	let impr_data = ref impr_policy_init in
	let improve x y =
		let (strat, impr) = impr_policy game node_compare !impr_data x y in
		impr_data := impr;
		strat
	in
	let evaluate = evaluate_strategy game node_compare in
	let improvable = strategy_improvable game node_compare in

    let counter = ref 0 in

	let strat = ref (init_strat game) in
    let valu = ref (evaluate !strat) in

	let rec get_desc game o i =
		match game#get_desc  i with Some s -> s | None -> ""
	in
    let show_eval _ =
        if !verbosity > 2 then (

            let g = game#subgame_by_edge_pred (new array_pg game#size) (fun u v -> (!strat)#get u = nd_undef || (!strat)#get u = v) in
	    game#iterate (fun i -> fun _ -> g#set_desc i (Some (string_of_int i ^ " : " ^ format_node_valuation (!valu).(i))));

(*            msg_tagged_nl 3 (fun _ -> "\nMade valuation:\n" ^ g#to_sring ^ "\n"); *)

	    let myfmt game strat =
	      let a = ref [] in
	      strat#iter (fun i j ->
	        if (j != nd_undef) && (ns_size (game#get_successors  i) > 1) && get_desc game i i != "" && get_desc game j j != ""
	        then a := (get_desc game i i ^ "->" ^ get_desc game j j)::!a
	      );
	      ListUtils.format (fun s -> s) (List.sort compare !a)
	    in
	    msg_tagged_nl 3 (fun _ -> "0-Strategy: " ^ myfmt game !strat ^ "\n");
	    let strat' = counter_strategy_by_valu_and_ordering game !valu node_compare in
	    msg_tagged_nl 3 (fun _ -> "1-Strategy: " ^ myfmt game strat' ^ "\n");
	    let impr = ref [] in
	    !strat#iter (fun i j ->
			 if j != nd_undef then ns_iter (fun k ->
						  if node_valuation_ordering game node_compare !valu.(j) !valu.(k) < 0
						  then impr := (i,k)::!impr
						 ) (game#get_successors  i)
			);
	    msg_tagged_nl 3 (fun _ -> "Improvement-Arena: " ^ ListUtils.format (fun (i,j) -> get_desc game i i ^ "->" ^ get_desc game j j) (List.sort compare !impr) ^ "\n")
        )
    in
    let show_changed oldstrat newstrat =
      if !verbosity > 2 then (
	let l = ref [] in
	oldstrat#iter (fun i j ->
		     if newstrat#get i != j then l := (i,j,newstrat#get i)::!l
		    );
	msg_tagged_nl 3 (fun _ -> "Strategy-Change: " ^ ListUtils.format (fun (i,j,k) -> get_desc game i i ^ "->" ^ get_desc game j j ^ "/" ^ get_desc game k k) (List.sort compare !l) ^ "\n")
      )
    in

    (* TEST *)
    let old = ref (-1) in
    let t = ref "" in
    let l = ref [] in
    (* TEST *)

    while (improvable !strat !valu) do
      show_eval ();
      incr counter;

      msg_tagged 2 (fun _ -> "Iteration: " ^ string_of_int !counter ^ "\r");

      (
	match !_strat_impr_callback with
	  None -> ()
	 |	Some c -> c !strat !counter
      );

      (* TEST *)
      if !enable_exp_bit_count then (
        let (s, v) = format_game_state game !valu in
        let s = string_of_int !counter ^ " : " ^ s in
	msg_tagged_nl 3 (fun _ -> "\nIteration: " ^ s ^ "\n");
        if (!old != v) || (!t <> s) then l := (s, v)::!l;
        t := s;
        old := v
      );
      (* TEST *)

      let old = !strat in
      strat := improve !strat !valu;
      show_changed old !strat;
      let valu' = evaluate !strat in
      if check_policy && (not (less_valuation (node_valuation_ordering game node_compare) !valu valu')) then (
	valu := valu';
        show_eval ();
        failwith "valuation improvement failure"
      );
      valu := valu'
    done;

    incr counter;
    (
      match !_strat_impr_callback with
	None -> ()
       |	Some c -> c !strat !counter
    );

    (* TEST *)
    if !enable_exp_bit_count then (
      let (s, v) = format_game_state game !valu in
      let s = string_of_int !counter ^ " : " ^ s in
      msg_tagged_nl 3 (fun _ -> "\nIteration: " ^ s ^ "\n");
      if (!old != v) || (!t <> s) then l := (s, v)::!l;
      t := s;
      old := v
    );
    (* TEST *)

    show_eval ();
    last_iteration_count := !counter;

    msg_plain 2 (fun _ -> "\n");

    (*TEST*)
    if !enable_exp_bit_count then (

      (*
        List.iter (fun (s, v) -> msg_tagged 2 (fun _ -> s ^ " = " ^ string_of_int v ^ "\n")) (List.rev !l);
       *)

      let l = transform_game_state_list !l in

      (*
        List.iter (fun (s, v) -> msg_tagged 2 (fun _ -> s ^ " = " ^ string_of_int v ^ "\n")) l;
       *)

      last_exp_bit_count := List.length l;
      msg_tagged 2 (fun _ -> "Bit Rounds: " ^ string_of_int !last_exp_bit_count ^ "\n")
    );
    (*TEST*)

    (winning_regions game !valu, winning_strategies game node_compare !strat !valu)




let strategy_improvement' (game: paritygame)
			  (init_strat: initial_strategy_fun)
			  (node_compare: node_total_ordering_fun)
			  (impr_policy: 'a improvement_policy_fun)
			  (impr_policy_init: 'a)
			  (check_policy: bool)
			  (ident: string) =
  let game' = alternating_transformation game true in
  let game'' = cheap_escape_cycles_transformation game' false in
  let (sol'', strat'') = strategy_improvement game'' init_strat node_compare impr_policy impr_policy_init check_policy ident in
  let sol = sol_init game' (fun v -> sol''#get v) in
  let strat = str_init game' (fun i -> strat''#get i) in
  let (sol', strat') = alternating_revertive_restriction game game' sol strat in
  for i = 0 to game#size  - 1 do
    if sol'#get i != game#get_owner  i then strat'#set i nd_undef
  done;
  (sol', strat');;

let strategy_improvement'' (game: paritygame)
			   (init_strat: initial_strategy_fun)
			   (node_compare: node_total_ordering_fun)
			   (impr_policy: 'a improvement_policy_fun)
			   (impr_policy_init: (paritygame -> 'a))
			   (check_policy: bool)
			   (ident: string) =
  let game' = cheap_escape_cycles_transformation game false in
  let (sol', strat') = strategy_improvement game' init_strat node_compare impr_policy (impr_policy_init game') check_policy ident in
  let sol = sol_init game (fun i -> sol'#get i) in
  let strat = str_init game (fun i -> strat'#get i) in
  (sol, strat);;

let improvement_policy_no_user_data imprpolicy = fun g o u s v -> (imprpolicy g o s v, u);;




let strategy_improvement_by_policy (game: paritygame) impr_policy impr_policy_init check_policy ident =
	strategy_improvement' game initial_strategy_by_last_edge node_total_ordering_by_position impr_policy impr_policy_init check_policy ident




let subsolvermap = ref TreeMap.empty_def;;

let register_sub_solver solver_func identifier abbreviation description =
	if TreeMap.mem identifier !subsolvermap
	then failwith ("Solver `" ^ identifier ^ "' already registered!\n")
	else subsolvermap := TreeMap.add identifier (solver_func, abbreviation, description) !subsolvermap;;

let mem_sub_solver identifier = TreeMap.mem identifier !subsolvermap;;

let find_sub_solver identifier = TreeMap.find identifier !subsolvermap;;

let enum_sub_solvers it = TreeMap.iter (fun i (f, a, d) -> it f i a d) !subsolvermap;;

let fold_sub_solvers fo b = TreeMap.fold (fun i (f, a, d) x -> fo f i a d x) !subsolvermap b;;



let improvement_policy_optimize_all_locally game node_total_ordering old_strategy valu =
	old_strategy#map (fun i j ->
		if j = nd_undef then nd_undef
		else let k = best_decision_by_valuation_ordering game node_total_ordering valu i in
			 if node_valuation_ordering game node_total_ordering valu.(j) valu.(k) < 0
			 then k
			 else j
	)

let improvement_policy_optimize_sequence game node_total_ordering old_strategy valu =
	let good p = p mod 2 = 0 in

	let update_summary summary p =
	  let idx = ref (-1) in
	  let goodidx = ref (-1) in
	  Array.iteri (fun i e ->
	    match e with
	    | Some q ->
	      if good q && !goodidx = i-1
	      then goodidx := i;
	      if q < p
	      then idx := i
	    | None -> ()
	  ) summary;
	  if good p && !goodidx >= !idx
	  then idx := !goodidx + 1;
	  Array.init (max (Array.length summary) (!idx + 1)) (fun i ->
	    if i < !idx then None
	    else if i = !idx then Some p
	    else summary.(i)
	  ) in

	let rec priopath_rev_to_summary = function
	  [] -> [||]
	| x::xs -> update_summary (priopath_rev_to_summary xs) x in

	let priopath_to_summary xs = priopath_rev_to_summary (List.rev xs) in

	let compare_summaries summary1 summary2 =
	  let mp = function
	    None -> 0
	  | Some p -> if good p then p + 1 else -(p + 1)
	  in
	  let l1 = Array.length summary1 in
	  let l2 = Array.length summary2 in
	  let result = ref 0 in
	  for i = (max l1 l2) - 1 downto 0 do
	    let e1 = mp (if i < l1 then summary1.(i) else None) in
	    let e2 = mp (if i < l2 then summary2.(i) else None) in
	    if !result = 0 && e1 != e2 then result := if e1 > e2 then 1 else -1
	  done;
	  !result in

	let counter = counter_strategy_by_valu_and_ordering game valu node_total_ordering in

  let node_path_by_valuation v =
		let visited = ref TreeSet.empty_def in
		let path = ref [] in
		let v = ref v in
		while not (TreeSet.mem !v !visited) do
		  path := !v::!path;
			visited := TreeSet.add !v !visited;
			v := if game#get_owner !v = plr_Even then old_strategy#get !v else counter#get !v
		done;
		List.rev !path
	in

	let node_path_to_prio_path = List.map game#get_priority in

	let node_summary v = priopath_to_summary (node_path_to_prio_path (node_path_by_valuation v)) in
(*
	 print_string (string_of_int (List.length (node_path_by_valuation 26)) ^ ArrayUtils.format (function None -> "N" | Some p -> string_of_int p) (node_summary 26) ^ "\n");
*)
  let any = ref false in
	let new_strategy = old_strategy#map (fun i j ->
		if j = nd_undef then nd_undef
		else let k = best_decision_by_ordering game (fun x y -> compare_summaries (node_summary x) (node_summary y)) i in
			 if node_valuation_ordering game node_total_ordering valu.(j) valu.(k) <= 0 && j !=k
			 then (any := true; k)
			 else j
	) in
	if !any then new_strategy else  (
		old_strategy#map (fun i j ->
			if j = nd_undef then nd_undef
			else let k = best_decision_by_valuation_ordering game node_total_ordering valu i in
				 if node_valuation_ordering game node_total_ordering valu.(j) valu.(k) < 0
				 then k
				 else j
		)		
		)


let strategy_improvement_optimize_all_locally_policy game =
	strategy_improvement game initial_strategy_by_best_reward node_total_ordering_by_position (improvement_policy_no_user_data improvement_policy_optimize_all_locally) () false "STRIMPR_LOCOPT";;

let strategy_improvement_optimize_sequence_policy game =
	strategy_improvement game initial_strategy_by_best_reward node_total_ordering_by_position (improvement_policy_no_user_data improvement_policy_optimize_sequence) () false "STRIMPR_LOCOPT";;




module CommandLine = struct
  let solve = ref (fun g -> universal_solve (universal_solve_init_options_verbose !universal_solve_global_options) strategy_improvement_optimize_all_locally_policy g)

  let speclist _ = fold_sub_solvers (fun solve' ident abbrev desc t ->
                          (["--" ^ ident; "-" ^ abbrev], Unit (fun _ -> solve := solve'), "\n     " ^ desc)::t) []

  let parse s =
  	SimpleArgs.parsearr s (speclist ()) (fun _ -> ()) "Policy Iteration Algorithm\n" SimpleArgs.argprint_help SimpleArgs.argprint_bad;
  	!solve

end ;;


open CommandLine ;;



let register _ =
    register_sub_solver
        (fun g -> universal_solve (universal_solve_init_options_verbose !universal_solve_global_options) strategy_improvement_optimize_all_locally_policy g)
        "switchall" "sa" "standard switch all policy iteration";
		register_sub_solver
        (fun g -> universal_solve (universal_solve_init_options_verbose !universal_solve_global_options) strategy_improvement_optimize_sequence_policy g)
        "switchseq" "sseq" "switch all sequency based policy iteration";
    Solverregistry.register_solver_factory (fun s -> parse s) "policyiter" "pi" "use policy iteration (see additional args)";;





type mdplike_valuation = (((int, float) TreeMap.t) * bool option) array




let compare_mdplike_valuation game valu v w =
	let cmprew = reward_total_ordering game node_total_ordering_by_priority_and_position in
	let vset = ref (empty_descending_relevance_ordered_set game node_total_ordering_by_priority_and_position) in
	let wset = ref (empty_descending_relevance_ordered_set game node_total_ordering_by_priority_and_position) in
	TreeMap.iter (fun k f -> vset := TreeSet.add k !vset) (fst valu.(v));
	TreeMap.iter (fun k f -> wset := TreeSet.add k !wset) (fst valu.(w));
	let c = ref 0 in
	while !c = 0 && not (TreeSet.is_empty !vset) && not (TreeSet.is_empty ! wset) do
		let vmax = TreeSet.min_elt !vset in
		vset := TreeSet.remove vmax !vset;
		let wmax = TreeSet.min_elt !wset in
		wset := TreeSet.remove wmax !wset;
		if (wmax = vmax) then (
		  let delta = TreeMap.find vmax (fst valu.(v)) -. TreeMap.find wmax (fst valu.(w)) in
			if (delta > 0.0 || delta < 0.0) then c := (if game#get_priority  vmax mod 2 = 0 then 1 else -1) * (if delta > 0.0 then 1 else -1)
		) else (
			c := cmprew vmax wmax
		)
	done;
	if (!c = 0 && not (TreeSet.is_empty !vset)) then c := (if game#get_priority  (TreeSet.min_elt !vset) mod 2 = 0 then 1 else -1)
	else if (!c = 0 && not (TreeSet.is_empty !wset)) then c := (if game#get_priority  (TreeSet.min_elt !wset) mod 2 = 0 then -1 else 1);
	(if (!c = 0 && snd valu.(v) != snd valu.(w)) then
		c := match (snd valu.(v), snd valu.(w)) with
		| (Some false, _) -> -1
		| (Some true, _) -> 1
		| (_, Some false) -> 1
		| (_, Some true) -> -1
		| _ -> 0);
	!c;;





let mdplike_valuation game minprio strategy =
	let n = game#size  in
	let valu = Array.make n (TreeMap.empty (flip (relevance_total_ordering game node_total_ordering_by_priority_and_position)), None) in
	let finished = Array.make n false in
	let queue = ref [] in
	game#iterate (fun i -> fun (pr,_,_,_,_) -> if pr = 1 then (
						   finished.(i) <- true;
						   queue := [i];
						 )) ;

	let is_cycle_node j = game#get_owner  j = plr_Even && ns_exists (fun k -> ns_exists (fun l -> l = j) (game#get_successors  k)) (game#get_successors  j) in
	while !queue != [] do
		let head = List.hd !queue in
		queue := List.tl !queue;
		ns_iter (fun i ->
			if not finished.(i) then (
				if game#get_owner  i = plr_Even && finished.(strategy#get i) then (
					valu.(i) <- valu.(strategy#get i);
					valu.(i) <- (TreeMap.add i 1.0 (fst valu.(i)), None);
					finished.(i) <- true;
					queue := i::!queue
				) else if game#get_owner  i = plr_Odd then (
					(* This is not the most general approach but good enough for what we are trying to do right now *)
					let nodes = ns_filter (fun j -> game#get_owner  j = plr_Odd || strategy#get j != i) (game#get_successors  i) in
  					let len = ns_size nodes in
	  				let nodes = if ns_size nodes < 2 then nodes else ns_filter is_cycle_node nodes in
					if (ns_forall (fun j -> finished.(j)) nodes) then (
						ns_iter (fun j ->
							TreeMap.iter (fun k v ->
								match TreeMap.find_opt k (fst valu.(i)) with
								| None -> valu.(i) <- (TreeMap.add k v (fst valu.(i)), None)
								| Some x -> valu.(i) <- (TreeMap.add k (v +. x) (fst valu.(i)), None)
							) (fst valu.(j))
						) nodes;
						TreeMap.iter (fun k v ->
							valu.(i) <- (TreeMap.add k (v /. float (ns_size nodes)) (fst valu.(i)), None)
						) (fst valu.(i));
						valu.(i) <- (TreeMap.add i 1.0 (fst valu.(i)), snd valu.(i));
						if (len > 1) then valu.(i) <- (fst valu.(i), None);
						finished.(i) <- true;
						queue := i::!queue
					)
				)
			)
		) (game#get_predecessors  head);
	done;
	game#iterate (fun i -> fun (_,ow,succs,_,_) ->
			     if ow = plr_Odd then (
			       let nodes = ns_filter (fun j -> game#get_owner  j = plr_Odd || strategy#get j != i) succs in
			       if ns_size nodes > 1 then (
				 let exit_node = ref (-1) in
				 ns_iter (fun j -> if not (is_cycle_node j) then exit_node := j) nodes;
				 let exit_node = !exit_node in
				 valu.(i) <- (fst valu.(i), Some (not (TreeMap.mem i (fst valu.(exit_node)))));
			       )
			     )) ;

	for i = 0 to n - 1 do
		valu.(i) <- (TreeMap.filter (fun j _ -> game#get_priority  j >= minprio) (fst valu.(i)), snd valu.(i));
	done;

	game#iterate (fun i -> fun (_,ow,succs,_,_) ->
			     if ow = plr_Odd && snd valu.(i) != None && OptionUtils.get_some (snd valu.(i)) = true then (
			       let nodes = ns_filter (fun j -> game#get_owner  j = plr_Odd || strategy#get j != i) succs in
			       if ns_size nodes > 1 then (
				 let exit_node = ref (-1) in
				 ns_iter (fun j -> if not (is_cycle_node j) then exit_node := j) nodes;
				 let exit_node = !exit_node in
				 valu.(i) <- (fst valu.(i), Some (compare_mdplike_valuation game valu exit_node i > 0));
			       )
			     )) ;

	let failed = ref false in
	for i = 0 to n - 1 do
		if (not finished.(i)) then failed := true;
	done;
	if (!failed) then (
		let g = game#subgame_by_strat (new array_pg game#size) strategy in
		g#iterate (fun i -> fun (_,_,_,_,d) -> g#set_desc i (Some ((OptionUtils.get_some d) ^ " - " ^ (if finished.(i) then "GOOD" else "BAD"))));
		g#print;
		failwith "failed";
	);
	valu;;
