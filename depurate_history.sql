-- Eliminar todo el historial de los dispositivos que NO están asignados a ninguna persona.
DELETE FROM public.device_history 
WHERE device_id IN (
  SELECT id FROM public.devices WHERE person_id IS NULL
);

-- (Opcional) Si en el futuro también quisieras borrar historial de equipos que 
-- ya ni siquiera existen en la tabla devices, descomenta esta línea:
-- DELETE FROM public.device_history WHERE device_id NOT IN (SELECT id FROM public.devices);
