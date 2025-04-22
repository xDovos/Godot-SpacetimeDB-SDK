use spacetimedb::{table, Identity, ReducerContext, Table};

use crate::{user, user_data};

#[table(name = lobby, public)]
pub struct Lobby {
    #[primary_key]
    #[auto_inc]
    id: u64,
    player_count: u32,
}

const MAX_PLAYERS_PER_LOBBY: u32 = 2;

pub fn user_disconnected(ctx: &ReducerContext, lobby_id: u64) {
    if let Some(mut lobby) = ctx.db.lobby().id().find(lobby_id) {
        if lobby.player_count > 0 {
            lobby.player_count -= 1;
            // log::info!(
            //     "Lobby {} player count decremented to {} after user {:?} disconnects",
            //     lobby.id,
            //     lobby.player_count,
            // );
            ctx.db.lobby().id().update(lobby);
        } else {
            log::warn!(
                "Attempted to decrement player count for lobby {} but it was already 0",
                lobby.id
            );
        }
    } else {
        // Лобби, в котором числился игрок, не найдено (уже удалено?)
        log::warn!("Lobby {} not found for disconnecting user", lobby_id);
    }
}
pub fn assign_user_to_lobby(ctx: &ReducerContext, user_identity: Identity) {
    let mut lobby_to_assign_id: Option<u64> = None;

    // Ищем первое лобби со свободным местом (< MAX_PLAYERS_PER_LOBBY игроков)
    // Используем filter и next() для более эффективного поиска по player_count
    if let Some(lobby) = ctx
        .db
        .lobby()
        .iter()
        .filter(|lobby| lobby.player_count < MAX_PLAYERS_PER_LOBBY)
        .next()
    {
        lobby_to_assign_id = Some(lobby.id);
        log::info!("Found existing lobby {} with space.", lobby.id);
    }

    let assigned_lobby_id: u64;

    match lobby_to_assign_id {
        Some(id) => {
            assigned_lobby_id = id;
        }
        None => {
            ctx.db.lobby().insert(Lobby {
                id: 0,
                player_count: 0,
            });

            if let Some(new_lobby) = ctx.db.lobby().iter().max_by_key(|lobby| lobby.id) {
                assigned_lobby_id = new_lobby.id;
                log::info!("Created new lobby {} and assigning user.", new_lobby.id);
            } else {
                // Error?
                log::error!(
                    "Failed to find newly created lobby (max ID) for user {:?}",
                    user_identity
                );
                assigned_lobby_id = 0;
            }
        }
    }

    // Обновляем lobby_id у пользователя
    if let Some(mut user) = ctx.db.user().identity().find(user_identity) {
        user.lobby_id = assigned_lobby_id;
        ctx.db.user().identity().update(user);
        log::info!(
            "Updated user {:?} lobby_id to {}",
            user_identity,
            assigned_lobby_id
        );
        if let Some(mut user_data) = ctx.db.user_data().identity().find(user_identity) {
            // Находим UserData
            user_data.lobby_id = assigned_lobby_id; // Устанавливаем ID
            ctx.db.user_data().identity().update(user_data); // <-- ДОБАВИТЬ ЭТО! Записываем изменения
            log::info!(
                "Updated user_data for {:?} lobby_id to {}",
                user_identity,
                assigned_lobby_id
            );
        } else {
            // Этого не должно происходить, если UserData создается в client_connected
            log::error!(
                "UserData not found when trying to assign lobby for user {:?}",
                user_identity
            );
        }

        // Увеличиваем счетчик игроков в лобби, куда назначен игрок
        if assigned_lobby_id != 0 {
            // Если игрок назначен не в "неназначенное" лобби
            if let Some(mut lobby) = ctx.db.lobby().id().find(assigned_lobby_id) {
                lobby.player_count += 1;
                log::info!(
                    "Lobby {} player count incremented to {}",
                    lobby.id,
                    lobby.player_count
                );
                ctx.db.lobby().id().update(lobby);
            } else {
                // Этого также не должно произойти, если assigned_lobby_id != 0
                log::error!("Assigned user to lobby {} but lobby not found to increment count for user {:?}", assigned_lobby_id, user_identity);
            }
        }
    } else {
        log::error!(
            "Attempted to assign lobby to unknown user {:?}",
            user_identity
        );
    }
}
