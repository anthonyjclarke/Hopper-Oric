# Hopper – The Original Release

---

## The Game

I wrote *Hopper* for the Oric-1, and PSS (Personal Software Services, 452 Stoney Stanton Road, Coventry) published it
on cassette in 1983, alongside my other Oric game, [*Light Cycle*](https://github.com/anthonyjclarke/Light-Cycle-Oric).
The game's own credits name me as the author and PSS as the publisher. Everything in this repository starts from the
tape image `original/HOPPER.TAP`.

---

## The Cassette

The front of the inlay has the PSS logo, the title, a frog in front of a lorry, and "Arcade action for ORIC 1" with the
catalogue number 010 on the strip below. The spine carries the title and "ORIC 1".

![The PSS cassette inlay for Hopper](images/original/inlay.png)

This is a straight scan of the cover painting. The C64 start-up picture is made from it
([graphics.md](graphics.md#the-c64-start-up-picture)).

![The cover painting](images/original/cover.png)

---

## The PSS Advert

PSS ran a full-page advert, "Real Software for your Oric 1", with the *Hopper* cover bottom right. It lists the game at
£6.95 among the titles available now, beside Centipede, Invaders and the Oric-Mon monitor, with *Light Cycle* and *The
Ultra* "available soon". The blurb calls Hopper an all machine code version of *Frogger* for the Oric 1, with variable
speed traffic, a three-lane highway, snakes, turtles, diving turtles, fleas (the fly), logs, a decreasing time limit,
ever increasing game speed, a hi-score table, full colour and sound.

![The PSS advert for its Oric 1 range, with the Hopper cover](images/original/pss-advert.jpg)

Everything the advert lists is there in the code: three road lanes, the snake on the middle bank, diving turtles from
sheet 2, the fly from sheet 3, the TIME limit, the speed-ups as sheets are cleared, and the eight-entry hi-score table
([player_guide.md](player_guide.md)).

---

## Oric-Mon

I wrote *Hopper* with Oric-Mon, a machine code monitor for the Oric-1 that PSS also published in 1983, credited to A. J.
Clarke. It's in the PSS advert above, beside *Hopper*. I pulled it together rather than writing all of it: some of it
wasn't my own work, and I can't remember now where those parts came from. What it gave me was a way to type the code
straight in, then disassemble it and check it as I went along. That way of working shows in *Hopper*: routines on
round addresses, fill bytes between them, `nop` runs where code was taken out, and a hidden exit to `$A800`
([quirks.md](quirks.md)).

Oric-Mon has its own page on oric.org: [Oric-Mon](https://www.oric.org/software/oric_mon-79.html). It has the tape
images, the inlay, scans of the tape labels, two screenshots and the manual, in English and in French. The page records
two releases:

| Release | Machines       | Tape                                                    | Manual  |
|:--------|:---------------|:--------------------------------------------------------|:--------|
| First   | Oric-1         | `oricmon.tap`                                           | English |
| Second  | Oric-1, Atmos  | Side 1 `oricmono.tap` (Oric-1); side 2 `oricmona.tap`   | French  |

The second release used the same "Oric-1" inlay with a yellow "Atmos compatible" sticker added. Its side 1 is the
Oric-1 version with the end address cut from `$B1FF` to `$B180`, because the bytes past `$B180` were only whatever was in
memory when the tape was saved. The page recommends the English manual over the French one.

Oric-Mon is the next Oric restoration after *Hopper* and *Light Cycle*, along with John Marshall's *The Ultra*
([credits.md](credits.md)).
