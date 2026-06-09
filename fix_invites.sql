-- 1. Drop existing problematic policies
DROP POLICY IF EXISTS "Guests can view their invites" ON public.network_shares;
DROP POLICY IF EXISTS "Guests can accept/reject invites" ON public.network_shares;

-- 2. Create new policies using auth.jwt() which is 100% reliable and doesn't need table permissions
CREATE POLICY "Guests can view their invites" ON public.network_shares FOR SELECT USING (
  guest_email = (auth.jwt() ->> 'email')::text
);

CREATE POLICY "Guests can accept/reject invites" ON public.network_shares FOR UPDATE USING (
  guest_email = (auth.jwt() ->> 'email')::text
);

-- 3. Also update the devices and networks policies to use auth.jwt() for the guest check
DROP POLICY IF EXISTS "Users can view owned or shared networks" ON public.networks;
CREATE POLICY "Users can view owned or shared networks" ON public.networks FOR SELECT USING (
  auth.uid() = owner_id OR 
  EXISTS (
    SELECT 1 FROM public.network_shares 
    WHERE network_shares.network_id = networks.id 
    AND network_shares.guest_email = (auth.jwt() ->> 'email')::text
    AND network_shares.status = 'accepted'
  )
);

DROP POLICY IF EXISTS "Users can update owned or shared networks" ON public.networks;
CREATE POLICY "Users can update owned or shared networks" ON public.networks FOR UPDATE USING (
  auth.uid() = owner_id OR 
  EXISTS (
    SELECT 1 FROM public.network_shares 
    WHERE network_shares.network_id = networks.id 
    AND network_shares.guest_email = (auth.jwt() ->> 'email')::text
    AND network_shares.status = 'accepted'
  )
);

DROP POLICY IF EXISTS "Users can access devices for accessible networks" ON public.devices;
CREATE POLICY "Users can access devices for accessible networks" ON public.devices FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.networks 
    WHERE networks.id = devices.network_id 
    AND (
      networks.owner_id = auth.uid() OR 
      EXISTS (
        SELECT 1 FROM public.network_shares 
        WHERE network_shares.network_id = networks.id 
        AND network_shares.guest_email = (auth.jwt() ->> 'email')::text
        AND network_shares.status = 'accepted'
      )
    )
  )
);

DROP POLICY IF EXISTS "Users can access history for accessible networks" ON public.device_history;
CREATE POLICY "Users can access history for accessible networks" ON public.device_history FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.devices 
    JOIN public.networks ON networks.id = devices.network_id
    WHERE devices.id = device_history.device_id
    AND (
      networks.owner_id = auth.uid() OR 
      EXISTS (
        SELECT 1 FROM public.network_shares 
        WHERE network_shares.network_id = networks.id 
        AND network_shares.guest_email = (auth.jwt() ->> 'email')::text
        AND network_shares.status = 'accepted'
      )
    )
  )
);
