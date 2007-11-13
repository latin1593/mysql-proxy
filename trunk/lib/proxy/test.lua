module("proxy.test", package.seeall)

local function boom(cond, msg, usermsg) 
	if not cond then
		local trace = debug.traceback()
		local e = {
			message = msg, 
			testmessage = usermsg, 
		}

		e.trace = "\n"
		local after_assert = false

		for line in trace:gmatch("([^\n]*)\n") do
			if after_assert then
				e.trace = e.trace .. line .. "\n"
			else
				after_assert = line:find("assert", 1, true)
			end
		end

		error(e)
	end
end

function assertEquals(is, expected, msg)
	boom(type(is) == type(expected), string.format("got type '%s' for <%s>, expected type '%s' for <%s>", 
		type(is), tostring(is), 
		type(expected), tostring(expected)),
		msg)
	boom(is == expected, string.format("got '%s' <%s>, expected '%s' <%s>", 
		tostring(is), type(is), 
		tostring(expected), type(expected)),
		msg)
end

function assertNotEquals(is, expected, msg)
	boom(is ~= expected, string.format("got '%s' <%s>, expected all but '%s' <%s>", 
		tostring(is), type(is), 
		tostring(expected), type(expected)),
		msg)
end

---
-- base class for all tests
--
-- overwrite setUp() and tearDown() when needed
BaseTest = { } 
function BaseTest:setUp() end
function BaseTest:tearDown() end
function BaseTest:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

-- extend the base class
ProxyBaseTest = BaseTest:new()

function ProxyBaseTest:setDefaultScope() 
	-- the fake script scope
	local proxy = {
		global = {
			config = {}
		},
		queries = {
			append = function (id, query) 
				queries[#queries + 1] = { 
					id = id, 
					query = query
				}
			end
		},
		connection = {
			server = {
			},
			client = {
			}
		},
		PROXY_SEND_RESULT = 1,
		PROXY_SEND_QUERY = 2,
	
		COM_SLEEP = 0,
		COM_QUIT = 1,
		COM_INIT_DB = 2,
		COM_QUERY = 3,
		COM_FIELD_LIST = 4,
		COM_CREATE_DB = 5,
		COM_DROP_DB = 6,
		COM_REFRESH = 7,
		COM_SHUTDOWN = 8,
		COM_STATISTICS = 9,
		COM_PROCESS_INFO = 10,
		COM_CONNECT = 11,
		COM_PROCESS_KILL = 12,
		COM_DEBUG = 13,
		COM_PING = 14,
		COM_TIME = 15,
		COM_DELAYED_INSERT = 16,
		COM_CHANGE_USER = 17,
		COM_BINLOG_DUMP = 18,
		COM_TABLE_DUMP = 19,
		COM_CONNECT_OUT = 20,
		COM_REGISTER_SLAVE = 21,
		COM_STMT_PREPARE = 22,
		COM_STMT_EXECUTE = 23,
		COM_STMT_SEND_LONG_DATA = 24,
		COM_STMT_CLOSE = 25,
		COM_STMT_RESET = 26,
		COM_SET_OPTION = 27,
		COM_STMT_FETCH = 28,
		COM_DAEMON = 29,

		MYSQLD_PACKET_OK = 0,
	}
	
	-- make access to the proxy.* strict
	setmetatable(proxy, {
		__index = function (tbl, key) error(("proxy.[%s] is unknown"):format(key)) end
	})

	_G.proxy           = proxy
end

---
-- result class for the test suite
--
-- feel free to overwrite print() to match your needs
Result = { 
	passed = 0,
	failed = 0,
	failed_tests = { }
}
function Result:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	return o
end

function Result:print()
	if self.failed > 0 then
		print("FAILED TESTS:")
		print(string.format("%-20s %-20s %-20s", "Class", "Testname", "Message"))
		print(string.rep("-", 63))
		for testclass, methods in pairs(self.failed_tests) do
			for methodname, err in pairs(methods) do
				print(string.format("%-20s %-20s %-20s\n%s", testclass, methodname, tostring(err.message), tostring(err.trace)))
				print(string.rep("-", 63))
			end
		end
	end
	print(string.format("%.02f%%, %d passed, %d failed", self.passed * 100 / ( self.passed + self.failed), self.passed, self.failed))
end

---
-- bundle tests into a test-suite
--
-- calls the setUp() and tearDown() methods before and after each
-- test
Suite = { }
function Suite:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self

	assert(o.result, "Suite:new(...) has be called with result = Result:new() to init the result handler")

	return o
end

function Suite:run(runclasses) 
	if not runclasses then
		runclasses = { }
		for testclassname, testclass in pairs(_G) do
			-- exec all the classes which start with Test
			if type(testclass) == "table" and testclassname:sub(1, 4) == "Test" then
				runclasses[#runclasses + 1] = testclassname
			end
		end
	end

	for runclassndx, testclassname in pairs(runclasses) do
		-- init the test-script
		local testclass = assert(_G[testclassname], "Class " .. testclassname .. " isn't known")

		local t = testclass:new()

		for testmethodname, testmethod in pairs(_G[testclassname]) do
			-- execute all the test functions
			if type(testmethod) == "function" and testmethodname:sub(1, 4) == "test" then
				t:setUp()

				local ok, err = pcall(t[testmethodname], t)

				if not ok then
					self.result.failed = self.result.failed + 1
					self.result.failed_tests[testclassname] = self.result.failed_tests[testclassname] or { }
					if type(err) == "string" then
						self.result.failed_tests[testclassname][testmethodname] = { 
							message = "compile error", 
							trace = "\n   "..err }
					else
						self.result.failed_tests[testclassname][testmethodname] = err
					end
				else
					self.result.passed = self.result.passed + 1
				end

				t:tearDown()
			end
		end
	end
end

function Suite:exit() 
	os.exit((self.result.failed == 0) and 0 or 1)
end

-- export the assert functions globally
_G.assertEquals    = assertEquals
_G.assertNotEquals = assertNotEquals

