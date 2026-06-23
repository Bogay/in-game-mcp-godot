const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { SSEClientTransport } = require('@modelcontextprotocol/sdk/client/sse.js');

// Simple client script simulating two AI agents (Agent 1 and Agent 2)
// connecting to the same running Godot process and playing the 2D RTS game.

async function startAgent(playerId, name) {
	console.log(`[${name}] Connecting to Godot MCP Server...`);
	const client = new Client(
		{ name: `rts-agent-${playerId}`, version: '1.0.0' },
		{ capabilities: {} }
	);
	
	const transport = new SSEClientTransport(new URL('http://127.0.0.1:9090/sse'));
	
	try {
		await client.connect(transport);
		console.log(`[${name}] Connected successfully!`);
		
		// Run a loop every 2 seconds
		const intervalId = setInterval(async () => {
			try {
				// 1. Get current game state
				const stateResponse = await client.callTool({
					name: 'aoe_get_game_state',
					arguments: { player_id: playerId }
				});
				
				if (stateResponse.isError) {
					console.error(`[${name}] Error getting game state:`, stateResponse.content[0].text);
					return;
				}
				
				const gameState = JSON.parse(stateResponse.content[0].text);
				const me = gameState.players.find(p => p.player_id === playerId);
				const otherPlayers = gameState.players.filter(p => p.player_id !== playerId);
				
				if (!me) {
					console.error(`[${name}] Player state not found!`);
					return;
				}
				
				// Extract my entities
				const myUnits = gameState.units.filter(u => u.owner_id === playerId);
				const myBuildings = gameState.buildings.filter(b => b.owner_id === playerId);
				
				const myVillagers = myUnits.filter(u => u.type === 'villager');
				const mySoldiers = myUnits.filter(u => u.type === 'soldier');
				
				const myTC = myBuildings.find(b => b.type === 'town_center');
				const myBarracks = myBuildings.find(b => b.type === 'barracks');
				
				// Resources
				const wood = me.wood;
				const gold = me.gold;
				const food = me.food;
				const pop = me.pop;
				const cap = me.cap;
				
				console.log(`[${name}] Stats - Food: ${food}, Wood: ${wood}, Gold: ${gold} | Pop: ${pop}/${cap} | Villagers: ${myVillagers.length}, Soldiers: ${mySoldiers.length}`);
				
				// 2. Decision Tree
				
				// A. BUILD HOUSES (if near population limit)
				if (pop >= cap - 1 && cap < 50 && wood >= 50) {
					// Check if a house is already under construction
					const houseUnderConstruction = myBuildings.some(b => b.type === 'house' && b.under_construction);
					if (!houseUnderConstruction) {
						const idleVillager = myVillagers.find(v => v.state === 'idle');
						if (idleVillager && myTC) {
							// Determine a build location near TC
							const bx = myTC.position[0] + (Math.random() > 0.5 ? 80 : -80) + Math.random() * 40 - 20;
							const by = myTC.position[1] + (Math.random() > 0.5 ? 80 : -80) + Math.random() * 40 - 20;
							
							console.log(`[${name}] Ordering Villager ${idleVillager.unit_id} to construct House at (${Math.round(bx)}, ${Math.round(by)}).`);
							await client.callTool({
								name: 'aoe_place_building',
								arguments: {
									player_id: playerId,
									villager_id: idleVillager.unit_id,
									building_type: 'house',
									x: bx,
									y: by
								}
							});
							return; // Skip other actions this tick
						}
					}
				}
				
				// B. BUILD BARRACKS (if none exists and we have enough wood)
				if (!myBarracks && wood >= 150) {
					// Check if a barracks is already under construction
					const barracksUnderConstruction = myBuildings.some(b => b.type === 'barracks' && b.under_construction);
					if (!barracksUnderConstruction) {
						const idleVillager = myVillagers.find(v => v.state === 'idle');
						if (idleVillager && myTC) {
							const bx = myTC.position[0] + (Math.random() > 0.5 ? 100 : -100);
							const by = myTC.position[1] + (Math.random() > 0.5 ? 100 : -100);
							
							console.log(`[${name}] Ordering Villager ${idleVillager.unit_id} to construct Barracks at (${Math.round(bx)}, ${Math.round(by)}).`);
							await client.callTool({
								name: 'aoe_place_building',
								arguments: {
									player_id: playerId,
									villager_id: idleVillager.unit_id,
									building_type: 'barracks',
									x: bx,
									y: by
								}
							});
							return;
						}
					}
				}
				
				// C. TRAIN VILLAGERS (if we have food, room in pop cap, and less than 7 villagers)
				if (food >= 50 && pop < cap && myVillagers.length < 7 && myTC && !myTC.under_construction) {
					const queueSize = myTC.spawn_queue ? myTC.spawn_queue.length : 0;
					if (queueSize < 2) {
						console.log(`[${name}] Training Villager at Town Center (ID: ${myTC.building_id}).`);
						await client.callTool({
							name: 'aoe_spawn_unit',
							arguments: {
								player_id: playerId,
								building_id: myTC.building_id,
								unit_type: 'villager'
							}
						});
					}
				}
				
				// D. TRAIN SOLDIERS (if we have a barracks and resources)
				if (food >= 50 && gold >= 30 && pop < cap && myBarracks && !myBarracks.under_construction) {
					const queueSize = myBarracks.spawn_queue ? myBarracks.spawn_queue.length : 0;
					if (queueSize < 2) {
						console.log(`[${name}] Training Soldier at Barracks (ID: ${myBarracks.building_id}).`);
						await client.callTool({
							name: 'aoe_spawn_unit',
							arguments: {
								player_id: playerId,
								building_id: myBarracks.building_id,
								unit_type: 'soldier'
							}
						});
					}
				}
				
				// E. GATHER RESOURCES (for idle villagers)
				const idleVillagers = myVillagers.filter(v => v.state === 'idle');
				for (const villager of idleVillagers) {
					// Check what resource we need most
					let targetType = 'tree'; // wood default
					if (food < 120 && food <= wood && food <= gold) {
						targetType = 'berry_bush';
					} else if (wood < 150 && wood <= gold) {
						targetType = 'tree';
					} else if (myBarracks) {
						targetType = 'gold_mine';
					}
					
					// Find nearest resource node of this type
					const resources = gameState.resources.filter(r => r.type === targetType && r.amount > 0);
					if (resources.length > 0) {
						// Calculate distances
						let nearest = resources[0];
						let minDist = Infinity;
						for (const res of resources) {
							const dx = res.position[0] - villager.position[0];
							const dy = res.position[1] - villager.position[1];
							const d = Math.sqrt(dx*dx + dy*dy);
							if (d < minDist) {
								minDist = d;
								nearest = res;
							}
						}
						
						console.log(`[${name}] Sending Villager ${villager.unit_id} to gather from resource ${nearest.resource_id} (${targetType}).`);
						await client.callTool({
							name: 'aoe_command_units',
							arguments: {
								player_id: playerId,
								unit_ids: [villager.unit_id],
								action: 'gather',
								target_id: nearest.resource_id
							}
						});
					}
				}
				
				// F. ATTACK ENEMIES (command soldiers)
				const idleSoldiers = mySoldiers.filter(s => s.state === 'idle');
				if (mySoldiers.length >= 3 && idleSoldiers.length > 0) {
					// We have an army! Let's attack the nearest enemy unit or building
					const enemies = [];
					
					// Add enemy units
					gameState.units.forEach(u => {
						if (u.owner_id !== playerId) enemies.push({ id: u.unit_id, pos: u.position, type: 'unit' });
					});
					
					// Add enemy buildings
					gameState.buildings.forEach(b => {
						if (b.owner_id !== playerId) enemies.push({ id: b.building_id, pos: b.position, type: 'building' });
					});
					
					if (enemies.length > 0) {
						// Find nearest enemy
						let targetEnemy = enemies[0];
						let minDist = Infinity;
						const leadSoldier = mySoldiers[0];
						
						for (const enemy of enemies) {
							const dx = enemy.pos[0] - leadSoldier.position[0];
							const dy = enemy.pos[1] - leadSoldier.position[1];
							const d = Math.sqrt(dx*dx + dy*dy);
							if (d < minDist) {
								minDist = d;
								targetEnemy = enemy;
							}
						}
						
						console.log(`[${name}] ATTACK! Ordering ${idleSoldiers.length} idle soldiers to attack enemy ${targetEnemy.id} (${targetEnemy.type}).`);
						await client.callTool({
							name: 'aoe_command_units',
							arguments: {
								player_id: playerId,
								unit_ids: idleSoldiers.map(s => s.unit_id),
								action: 'attack',
								target_id: targetEnemy.id
							}
						});
					}
				} else if (idleSoldiers.length > 0 && myTC) {
					// Guard TC
					const sIds = idleSoldiers.map(s => s.unit_id);
					const tx = myTC.position[0] + Math.random() * 40 - 20;
					const ty = myTC.position[1] + Math.random() * 40 - 20;
					console.log(`[${name}] Sending ${idleSoldiers.length} idle soldiers to guard Town Center.`);
					await client.callTool({
						name: 'aoe_command_units',
						arguments: {
							player_id: playerId,
							unit_ids: sIds,
							action: 'move',
							target_position: [tx, ty]
						}
					});
				}
				
			} catch (err) {
				console.error(`[${name}] Error in agent loop:`, err.message);
			}
		}, 2000);
		
		// Handle termination
		process.on('SIGINT', () => {
			clearInterval(intervalId);
			client.close();
			console.log(`[${name}] Shut down.`);
		});
		
	} catch (err) {
		console.error(`[${name}] Failed to connect:`, err.message);
	}
}

// Start both Agent 1 (Player 1) and Agent 2 (Player 2)
async function main() {
	console.log("==================================================");
	console.log("RTS MULTI-AGENT CLIENT MANAGER");
	console.log("Connecting Agent 1 (Player 1) and Agent 2 (Player 2)...");
	console.log("Make sure the Godot game is running first!");
	console.log("==================================================");
	
	startAgent(1, "Agent 1 (Red)");
	setTimeout(() => {
		startAgent(2, "Agent 2 (Green)");
	}, 500);
}

main();
