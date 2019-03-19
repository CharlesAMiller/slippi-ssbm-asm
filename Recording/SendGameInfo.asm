#To be inserted at 8016e74c
.include "../Common/Common.s"
.include "Recording.s"

################################################################################
# Routine: SendGameInfo
# ------------------------------------------------------------------------------
# Description: Gets the parameters that define the game such as stage,
# characters, settings, etc and write them out to Slippi device
################################################################################

.set REG_Buffer,30
.set REG_BufferOffset,29

backup

# Check if VS Mode
  branchl r12,FN_IsVSMode
  cmpwi r3,0x0
  beq Injection_Exit

# initialize the write buffer that will be used throughout the game
# according to UnclePunch, all allocated memory gets free'd when the scene
# transitions. This means we don't need to worry about freeing this memory

#Create write buffer
  li  r3,FULL_FRAME_DATA_BUF_LENGTH
  branchl r12,0x8037f1e4
  mr  REG_Buffer,r3
  stw REG_Buffer,frameDataBuffer(r13)
#Init current offset
  li  r3,0
  stw r3,bufferOffset(r13)
#Create secondary buffer
  li  r3,SECONDARY_DATA_BUF_LENGTH
  branchl r12,0x8037f1e4
  stw r3,secondaryDataBuffer(r13)

#------------- WRITE OUT COMMAND SIZES -------------
# start file sending and indicate the sizes of the output commands
  li r3, 0x35
  stb r3,0x0(REG_Buffer)

# write out the payload size of the 0x35 command (includes this byte)
# we can write this in only a byte because I doubt it will ever be larger
# than 255. We write out the sizes of the other commands as half words for
# consistent parsing
  li r3, MESSAGE_DESCIPTIONS_PAYLOAD_LENGTH
  stb r3,0x1(REG_Buffer)

# game info command
  li r3, 0x36
  stb r3,0x2(REG_Buffer)
  li r3, GAME_INFO_PAYLOAD_LENGTH
  sth r3,0x3(REG_Buffer)

# pre-frame update command
  li r3, 0x37
  stb r3,0x5(REG_Buffer)
  li r3, GAME_PRE_FRAME_PAYLOAD_LENGTH
  sth r3,0x6(REG_Buffer)

# post-frame update command
  li r3, 0x38
  stb r3,0x8(REG_Buffer)
  li r3, GAME_POST_FRAME_PAYLOAD_LENGTH
  sth r3,0x9(REG_Buffer)

# game end command
  li r3, 0x39
  stb r3,0xB(REG_Buffer)
  li r3, GAME_END_PAYLOAD_LENGTH
  sth r3,0xC(REG_Buffer)

#------------- BEGIN GAME INFO COMMAND -------------
# game information message type
  li r3, 0x36
  stb r3,0xE(REG_Buffer)

# build version number. Each byte is one digit
  load r3,CURRENT_VERSION
  stw r3,0xF(REG_Buffer)

#------------- GAME INFO BLOCK -------------
# this iterates through the static game info block that is used to pull data
# from to initialize the game. it writes out the whole thing (0x138 long)
.set GameInfoLength,0x138
.set GameInfoStart,0x13

  addi r3,REG_Buffer,GameInfoStart
  mr  r4,r31
  li  r5,GameInfoLength
  branchl r12,0x800031f4

#------------- ADJUST GAME INFO BLOCK FOR SHEIK -------------

.set REG_LoopCount,20
.set REG_PlayerDataStart,21

# Offsets
.set PlayerDataStart,96       #player data starts in match struct
.set PlayerDataLength,36      #length of each player's data
.set PlayerCharacter,0x0
.set PlayerStatus,0x1         #offset of players in-game status
.set Nametag,0xA              #offset of the nametag ID in the player's data

#Get game info in buffer
  addi  r3,REG_Buffer,GameInfoStart
#Get to player data
  addi  REG_PlayerDataStart,r3,PlayerDataStart
#Init Loop Count
  li  REG_LoopCount,0
SEND_GAME_INFO_EDIT_SHEIK_LOOP:
#Get start of this players data
  mulli r22,REG_LoopCount,PlayerDataLength
  add r22,r22,REG_PlayerDataStart
#Check if this player is active
  lbz r3,PlayerStatus(r22)
  cmpwi r3,0x0
  bne SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC
#Check if this player is zelda
  lbz r3,PlayerCharacter(r22)
  cmpwi r3,0x12
  bne SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC
#Check if this player is holding A
  load r3,0x804c20bc
  mulli	r4, REG_LoopCount, 68
  add r3,r3,r4
  lwz r3,0x0(r3)
  rlwinm.	r0, r3, 0, 23, 23
  beq SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC
#Change player to Sheik
  li  r3,0x13
  stb r3,PlayerCharacter(r22)

SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC:
  addi  REG_LoopCount,REG_LoopCount,1
  cmpwi REG_LoopCount,4
  blt SEND_GAME_INFO_EDIT_SHEIK_LOOP

#------------- OTHER INFO -------------
# write out random seed
  lis r3, 0x804D
  lwz r3, 0x5F90(r3) #load random seed
  stw r3, 0x14B(REG_Buffer)

#------------- SEND UCF Toggles ------------

.set UCFToggleStart,0x14F

# write UCF toggle bytes
  subi r20,rtoc,ControllerFixOptions    #Get UCF toggles
  li  r21,0                 #Init loop
  addi r22,REG_Buffer,UCFToggleStart
UCF_LOOP:
  mulli r23,r21,8
  lbzx r3,r21,r20           #Get toggle value
  stwx r3,r22,r23
  addi r23,r23,4            #Next offset
  stwx r3,r22,r23           #send toggle value again for compatibility with old .slp files
  addi  r21,r21,1
  cmpwi r21,4
  blt UCF_LOOP

#------------- SEND NAMETAGS ------------
# Loop through players 1-4 and send their nametag data
# r31 contains the match struct fed into StartMelee. We'll
# be using this to find each player's nametag slot

.set NametagDataStart,0x16F

# Offsets
.set PlayerDataStart,96       #player data starts in match struct
.set PlayerDataLength,36      #length of each player's data
.set PlayerStatus,0x1         #offset of players in-game status
.set Nametag,0xA              #offset of the nametag ID in the player's data
# Constants
.set CharactersToCopy, 8 *2
# Registers
.set REG_LoopCount,20
.set REG_PlayerDataStart,21
.set REG_CurrentPlayerData,22

# Init loop
  li  REG_LoopCount,0                               #init loop count
  addi REG_PlayerDataStart,r31,PlayerDataStart     #player data start in match struct
  addi r23,REG_Buffer,NametagDataStart              #Start of nametag data in buffer
SEND_GAME_INFO_NAMETAG_LOOP:
#Get nametag data in buffer in r24
  mulli r24,REG_LoopCount,CharactersToCopy
  add r24,r24,r23
# Get players data
  mulli REG_CurrentPlayerData,REG_LoopCount,PlayerDataLength
  add REG_CurrentPlayerData,REG_CurrentPlayerData,REG_PlayerDataStart
# Check if player is in game && human
  lbz r3,PlayerStatus(REG_CurrentPlayerData)
  cmpwi r3,0x0
  bne SEND_GAME_INFO_NAMETAG_NO_TAG
# Check if player has a nametag
  lbz r3,Nametag(REG_CurrentPlayerData)
  cmpwi r3,0x78
  beq SEND_GAME_INFO_NAMETAG_NO_TAG
#Get nametag string
  branchl r12,0x8023754c
# Copy first 8 characters to nametag to buffer
  mr  r4,r3
  mr  r3,r24
  li  r5,CharactersToCopy
  branchl r12,0x800031f4
  b SEND_GAME_INFO_NAMETAG_INC_LOOP

SEND_GAME_INFO_NAMETAG_NO_TAG:
# Fill with zeroes
  mr r3,r24
  li r4,CharactersToCopy
  branchl r12,0x8000c160

SEND_GAME_INFO_NAMETAG_INC_LOOP:
# Increment Loop
  addi REG_LoopCount,REG_LoopCount,1
  cmpwi REG_LoopCount,4
  blt SEND_GAME_INFO_NAMETAG_LOOP

#------------- SEND PAL Toggle ------------

  lbz r3,PALToggle(rtoc)
  stb r3,0x1AF(REG_Buffer)

#------------- Transfer Buffer ------------
  mr  r3,REG_Buffer
  li  r4,MESSAGE_DESCIPTIONS_PAYLOAD_LENGTH+1 + GAME_INFO_PAYLOAD_LENGTH+1
  li  r5,CONST_ExiWrite
  branchl r12,FN_EXITransferBuffer

Injection_Exit:
  restore
  lis	r3, 0x8017
