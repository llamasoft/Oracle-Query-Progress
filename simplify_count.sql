CREATE TYPE suffix_array IS TABLE OF VARCHAR2(32);
/

CREATE OR REPLACE FUNCTION simplify_core(
    qty         NUMBER,
    unit_base   NUMBER,
    str_format  VARCHAR2,
    suffixes    suffix_array
    ) RETURN VARCHAR2
IS
    magnitude   NUMBER;
    rtn         VARCHAR2(1024);
    max_rtn_len NUMBER;
BEGIN
    -- Can't format NULL, don't even try.
    IF (qty IS NULL) THEN
        RETURN NULL;
    END IF;

    -- Extract the longest suffix from the suffix list
    SELECT MAX(LENGTH(column_value)) INTO max_rtn_len FROM TABLE(suffixes);
    -- We add one to make sure there's room for a sign, add one again for quantity/suffix spacing
    max_rtn_len := max_rtn_len + LENGTH(str_format) + 2;


    -- Cannot take LOG(0), so handle that here
    IF (NVL(qty, 0) = 0) THEN
        magnitude := 0;

    ELSE
        -- Determine what order of magnitude the quantity is.
        -- Each order of magnitude moves the suffix selection forward one.
        -- e.g.: 1000K = 1M, 1000M = 1B, ...
        -- We can't take LOG(negative) either, so use ABS(qty).
        --   We'll fix the sign later.
        magnitude := FLOOR(LOG(unit_base, ABS(qty)));

        -- Make sure we're still within the bounds of the suffix list
        magnitude := LEAST(magnitude, suffixes.count);
    END IF;


    -- Scale down the quantity by base^magnitude and add the suffix.
    --   We use suffixes(magnitude + 1) because of 1-indexed PL/SQL arrays.
    -- We don't have to worry about the result sign because magnitude is always positive.
    rtn := TO_CHAR(qty / POWER(unit_base, magnitude), str_format) || ' ' || suffixes(magnitude + 1);
    RETURN LPAD(RTRIM(rtn), max_rtn_len);
END;
/

CREATE OR REPLACE FUNCTION simplify_count(
    qty         NUMBER,
    unit_base   NUMBER DEFAULT 1000,
    str_format  NUMBER DEFAULT '999.9',
    suffixes    suffix_array DEFAULT suffix_array('', 'K', 'M', 'B', 'T', 'Qu', 'Qi', 'Sx', 'Sp')
    ) RETURN VARCHAR2
IS
BEGIN
    RETURN simplify_core(qty, unit_base, str_format, suffixes);
END;
/

CREATE OR REPLACE FUNCTION simplify_size(
    qty         NUMBER,
    unit_base   NUMBER DEFAULT 1024,
    str_format  NUMBER DEFAULT '999.9',
    suffixes    suffix_array DEFAULT suffix_array('B', 'K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')
    ) RETURN VARCHAR2
IS
BEGIN
    RETURN simplify_core(qty, unit_base, str_format, suffixes);
END;
/

CREATE OR REPLACE PUBLIC SYNONYM suffix_array   FOR suffix_array;
CREATE OR REPLACE PUBLIC SYNONYM simplify_core  FOR simplify_core;
CREATE OR REPLACE PUBLIC SYNONYM simplify_count FOR simplify_count;
CREATE OR REPLACE PUBLIC SYNONYM simplify_size  FOR simplify_size;

GRANT EXECUTE ON suffix_array   TO PUBLIC;
GRANT EXECUTE ON simplify_core  TO PUBLIC;
GRANT EXECUTE ON simplify_count TO PUBLIC;
GRANT EXECUTE ON simplify_size  TO PUBLIC;

