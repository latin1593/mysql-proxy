#  $%BEGINLICENSE%$
#  Copyright (c) 2009, 2012, Oracle and/or its affiliates. All rights reserved.
# 
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License as
#  published by the Free Software Foundation; version 2 of the
#  License.
# 
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
# 
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
#  02110-1301  USA
# 
#  $%ENDLICENSE%$
ADD_SUBDIRECTORY(proxy)

INSTALL(FILES
	active-queries.lua
	active-transactions.lua
	admin-sql.lua
	analyze-query.lua
	auditing.lua
	commit-obfuscator.lua
	commit-obfuscator.msc
	histogram.lua
	load-multi.lua
	ro-balance.lua
	ro-pooling.lua
	rw-splitting.lua
	xtab.lua

	DESTINATION share/doc/mysql-proxy/
)

INSTALL(FILES
	admin.lua

	DESTINATION lib/mysql-proxy/lua/
)


INCLUDE_DIRECTORIES(${GLIB_INCLUDE_DIRS})
LINK_DIRECTORIES(${GLIB_LIBRARY_DIRS})
LINK_DIRECTORIES(${LIBINTL_LIBRARY_DIRS})

INCLUDE_DIRECTORIES(${LUA_INCLUDE_DIRS})
LINK_DIRECTORIES(${LUA_LIBRARY_DIRS})

INCLUDE_DIRECTORIES(${CMAKE_SOURCE_DIR}/src/)
INCLUDE_DIRECTORIES(${PROJECT_BINARY_DIR}) # for config.h

INCLUDE_DIRECTORIES(${MYSQL_INCLUDE_DIRS})
INCLUDE_DIRECTORIES(${EVENT_INCLUDE_DIRS})
INCLUDE_DIRECTORIES(${CMAKE_CURRENT_BINARY_DIR}) ## for the generated header file
INCLUDE_DIRECTORIES(${CMAKE_CURRENT_SOURCE_DIR}) ## for the packaged header file

## don't require flex if we have sql-tokenizer.c in the source-dir
## already as it was placed there at "make dist" time.
SET(SQL_TOKENIZER_C "${CMAKE_CURRENT_SOURCE_DIR}/sql-tokenizer.c")

IF(NOT EXISTS ${SQL_TOKENIZER_C})
	FIND_PROGRAM(FLEX_EXECUTABLE NAMES flex DOC "full path of flex")
	IF(NOT FLEX_EXECUTABLE)
		MESSAGE(SEND_ERROR "flex wasn't found, -DFLEX_EXECUTABLE=...")
	ENDIF()

	SET(SQL_TOKENIZER_C "${CMAKE_CURRENT_BINARY_DIR}/sql-tokenizer.c")
	ADD_CUSTOM_COMMAND(
		OUTPUT  ${SQL_TOKENIZER_C}
		DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/sql-tokenizer.l"
		COMMAND ${FLEX_EXECUTABLE} 
			-o ${SQL_TOKENIZER_C}
			"${CMAKE_CURRENT_SOURCE_DIR}/sql-tokenizer.l"
	)
	SET_SOURCE_FILES_PROPERTIES(${SQL_TOKENIZER_C}
		PROPERTIES GENERATED 1)
ENDIF()

ADD_EXECUTABLE(sql-tokenizer-gen
	sql-tokenizer-tokens.c
	sql-tokenizer-gen.c)
TARGET_LINK_LIBRARIES(sql-tokenizer-gen
	${GLIB_LIBRARIES}
)

ADD_CUSTOM_COMMAND(
	OUTPUT  "${CMAKE_CURRENT_BINARY_DIR}/sql-tokenizer-keywords.c"
	DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/sql-tokenizer-gen.c"
	COMMAND sql-tokenizer-gen 
		> "${CMAKE_CURRENT_BINARY_DIR}/sql-tokenizer-keywords.c"
)

SET(LUA_GLIB2_SOURCES
	glib2.c
)
SET(LUA_LFS_SOURCES
	lfs.c
)
SET(LUA_MYSQL_SOURCES
	mysql-proto.c
	${SQL_TOKENIZER_C}
	sql-tokenizer-keywords.c 
	sql-tokenizer-tokens.c 
	sql-tokenizer-lua.c 
)

SET(LUA_CHASSIS_SOURCES
	chassis.c
)

SET(LUA_LPEG_SOURCES
	lpeg.c
)

IF(WIN32)
	SET(LUA_GLIB2_SOURCES ${LUA_GLIB2_SOURCES} glib2.def)
	SET(LUA_LFS_SOURCES ${LUA_LFS_SOURCES} lfs.def)
	SET(LUA_MYSQL_SOURCES ${LUA_MYSQL_SOURCES} mysql.def)
	SET(LUA_CHASSIS_SOURCES ${LUA_CHASSIS_SOURCES} chassis.def)
	SET(LUA_LPEG_SOURCES ${LUA_LPEG_SOURCES} lpeg.def)
ENDIF(WIN32)

ADD_LIBRARY(glib2   SHARED ${LUA_GLIB2_SOURCES})
ADD_LIBRARY(lfs     SHARED ${LUA_LFS_SOURCES})
ADD_LIBRARY(mysql   SHARED ${LUA_MYSQL_SOURCES})
ADD_LIBRARY(chassis SHARED ${LUA_CHASSIS_SOURCES})
ADD_LIBRARY(lpeg    SHARED ${LUA_LPEG_SOURCES})


### 
## building the lua extensions that can be loaded with require()
##
## if possible don't link them against liblua.a, the caller will provide all the symbols
## on win32 we have to link against it, but they have a .dll by default

IF(WIN32)
	## win32 is the only platform that needs reference to the lua.dll at linktime
	SET(LUA_SHARED_LIBRARIES ${LUA_LIBRARIES})

	TARGET_LINK_LIBRARIES(lfs
		${LUA_SHARED_LIBRARIES})
	TARGET_LINK_LIBRARIES(lpeg
		${LUA_SHARED_LIBRARIES})
ELSE(WIN32)
	SET(LUA_SHARED_LIBRARIES )
ENDIF(WIN32)

IF(APPLE)
	## MacOSX may have a static liblua and we don't want to link that in
	SET_TARGET_PROPERTIES(
		glib2 lfs lpeg
		PROPERTIES 
			LINK_FLAGS "-undefined dynamic_lookup")
ENDIF(APPLE)

TARGET_LINK_LIBRARIES(glib2
	${LUA_SHARED_LIBRARIES}
	${GLIB_LIBRARIES}
)
TARGET_LINK_LIBRARIES(mysql 
	${LUA_SHARED_LIBRARIES}
	${GLIB_LIBRARIES}
	mysql-chassis-proxy
)
TARGET_LINK_LIBRARIES(chassis 
	${LUA_SHARED_LIBRARIES}
	${GLIB_LIBRARIES}
	mysql-chassis
)

MACRO(LUAMODULE_INSTALL _plugin_name)
	IF(NOT WIN32)
		## remove the "lib" prefix on Unix platforms to make the modules loadable
		INSTALL(FILES ${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_SHARED_LIBRARY_PREFIX}${_plugin_name}${CMAKE_SHARED_LIBRARY_SUFFIX}
			DESTINATION lib/mysql-proxy/lua/
			RENAME ${_plugin_name}${CMAKE_SHARED_LIBRARY_SUFFIX}
		)
	ELSE(NOT WIN32)
		## on win32 the lua module gets prefixed with lua- and end up in bin/
		INSTALL(FILES ${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_BUILD_TYPE}/${CMAKE_SHARED_LIBRARY_PREFIX}${_plugin_name}${CMAKE_SHARED_LIBRARY_SUFFIX}
			DESTINATION bin/
			RENAME lua-${_plugin_name}${CMAKE_SHARED_LIBRARY_SUFFIX}
		)
	ENDIF(NOT WIN32)
ENDMACRO(LUAMODULE_INSTALL _plugin_name)

LUAMODULE_INSTALL(glib2)
LUAMODULE_INSTALL(lfs)
LUAMODULE_INSTALL(lpeg)
LUAMODULE_INSTALL(mysql)
LUAMODULE_INSTALL(chassis)

