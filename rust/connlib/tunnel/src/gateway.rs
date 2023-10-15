use crate::device_channel::create_iface;
use crate::{
    ControlSignal, Device, Event, RoleState, Tunnel, ICE_GATHERING_TIMEOUT_SECONDS,
    MAX_CONCURRENT_ICE_GATHERING, MAX_UDP_SIZE,
};
use connlib_shared::error::ConnlibError;
use connlib_shared::messages::{ClientId, Interface as InterfaceConfig};
use connlib_shared::Callbacks;
use futures::channel::mpsc::Receiver;
use futures_bounded::{PushError, StreamMap};
use std::sync::Arc;
use std::task::{ready, Context, Poll};
use std::time::Duration;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;

impl<C, CB> Tunnel<C, CB, GatewayState>
where
    C: ControlSignal + Send + Sync + 'static,
    CB: Callbacks + 'static,
{
    /// Sets the interface configuration and starts background tasks.
    #[tracing::instrument(level = "trace", skip(self))]
    pub async fn set_interface(
        self: &Arc<Self>,
        config: &InterfaceConfig,
    ) -> connlib_shared::Result<()> {
        let device = create_iface(config, self.callbacks()).await?;
        *self.device.write().await = Some(device.clone());

        self.start_timers().await?;
        *self.iface_handler_abort.lock() =
            Some(tokio::spawn(device_handler(Arc::clone(self), device)).abort_handle());

        tracing::debug!("background_loop_started");

        Ok(())
    }
}

/// Reads IP packets from the [`Device`] and handles them accordingly.
async fn device_handler<C, CB>(
    tunnel: Arc<Tunnel<C, CB, GatewayState>>,
    mut device: Device,
) -> Result<(), ConnlibError>
where
    C: ControlSignal + Send + Sync + 'static,
    CB: Callbacks + 'static,
{
    let mut buf = [0u8; MAX_UDP_SIZE];
    loop {
        let Some(packet) = device.read().await? else {
            // Reading a bad IP packet or otherwise from the device seems bad. Should we restart the tunnel or something?
            return Ok(());
        };

        let dest = packet.destination();

        let Some(peer) = tunnel.peer_by_ip(dest) else {
            continue;
        };

        if let Err(e) = tunnel
            .encapsulate_and_send_to_peer(packet, peer, &dest, &mut buf)
            .await
        {
            tracing::error!(err = ?e, "failed to handle packet {e:#}")
        }
    }
}

/// [`Tunnel`] state specific to gateways.
pub struct GatewayState {
    candidate_receivers: StreamMap<ClientId, RTCIceCandidateInit>,
}

impl GatewayState {
    pub fn add_new_ice_receiver(&mut self, id: ClientId, receiver: Receiver<RTCIceCandidateInit>) {
        match self.candidate_receivers.try_push(id, receiver) {
            Ok(()) => {}
            Err(PushError::BeyondCapacity(_)) => {
                tracing::warn!("Too many active ICE candidate receivers at a time")
            }
            Err(PushError::Replaced(_)) => {
                tracing::warn!(%id, "Replaced old ICE candidate receiver with new one")
            }
        }
    }
}

impl Default for GatewayState {
    fn default() -> Self {
        Self {
            candidate_receivers: StreamMap::new(
                Duration::from_secs(ICE_GATHERING_TIMEOUT_SECONDS),
                MAX_CONCURRENT_ICE_GATHERING,
            ),
        }
    }
}

impl RoleState for GatewayState {
    type Id = ClientId;

    fn poll_next_event(&mut self, cx: &mut Context<'_>) -> Poll<Event<Self::Id>> {
        loop {
            match ready!(self.candidate_receivers.poll_next_unpin(cx)) {
                (conn_id, Some(Ok(c))) => {
                    return Poll::Ready(Event::SignalIceCandidate {
                        conn_id,
                        candidate: c,
                    })
                }
                (id, Some(Err(e))) => {
                    tracing::warn!(gateway_id = %id, "ICE gathering timed out: {e}")
                }
                (_, None) => {}
            }
        }
    }
}