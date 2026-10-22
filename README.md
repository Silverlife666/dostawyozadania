# Harmonogram zadań i dostaw

Wersja korzysta z Supabase zamiast npoint. Dane planu, konta i uprawnienia są
egzekwowane po stronie bazy przez RLS; strona GitHub Pages nie używa ani nie
zawiera klucza `service_role`.

## Jednorazowe uruchomienie

1. W Supabase SQL Editor uruchom cały plik `supabase/schema.sql`.
2. W `Authentication -> Users` utwórz trzy konta. E-mail jest loginem, a hasło
   może być numerycznym PIN-em:
   - Administrator,
   - Właściciel,
   - Pracownik.
3. W tabeli `delivery_schedule_users` odszukaj pierwsze konto i uruchom w SQL
   Editor polecenie z początku `schema.sql`, podstawiając jego UUID. To aktywuje
   konto Administratora. Pozostałe konta aktywuj i konfiguruj z panelu
   Administratora w aplikacji.
4. W `index.html` uzupełnij wyłącznie `SUPABASE_URL` i
   `SUPABASE_ANON_KEY`. Klucz anon/publishable jest przeznaczony do aplikacji
   przeglądarkowej; **nigdy** nie wklejaj tam `service_role` ani `sb_secret`.
5. Jednorazowo przenieś obecny plan npoint po ustawieniu lokalnie zmiennych
   `SUPABASE_URL` oraz `SUPABASE_SERVICE_ROLE_KEY`:

   ```powershell
   python scripts/migrate_npoint_to_supabase.py
   ```

   Skrypt zapisuje tylko rekord planu `delivery_schedule_state`.

W ustawieniach Supabase Auth wyłącz publiczne rejestrowanie kont, ponieważ
konta mają być zakładane wyłącznie przez administratora.

## Uprawnienia

Administrator ma pełny dostęp. Właściciel i Pracownik dostają indywidualne
uprawnienia: edycja planu, zarządzanie osobami/firmami i pobieranie PDF.
Wyczyszczenie istniejących zadań jest dodatkowo blokowane po
stronie Supabase dla każdej roli poza Administratorem.
