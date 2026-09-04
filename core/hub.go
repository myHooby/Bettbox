package main

import (
	"bytes"
	"context"
	"core/state"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"runtime"
	"runtime/debug"
	"sort"
	"strconv"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/common/yaml"
	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/component/ca"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	mihomoNtp "github.com/metacubex/mihomo/ntp/ntp"
	rulesProvider "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"github.com/metacubex/http"
	"sync"
)

var (
	isInit            = false
	externalProviders = map[string]cp.Provider{}
	logSubscriber     observable.Subscription[log.Event]
	ageMutex          sync.Mutex
)

func handleInitClash(paramsString string) bool {
	var params = InitParams{}
	err := json.Unmarshal([]byte(paramsString), &params)
	if err != nil {
		return false
	}
	version = params.Version
	if !isInit {
		constant.SetHomeDir(params.HomeDir)
		isInit = true
	}
	return isInit
}

func handleStartListener() bool {
	runLock.Lock()
	defer runLock.Unlock()
	isRunning = true
	updateListeners()
	resolver.ResetConnection()
	return true
}

func handleStopListener() bool {
	runLock.Lock()
	defer runLock.Unlock()
	isRunning = false
	listener.StopListener()
	return true
}

func handleGetIsInit() bool {
	return isInit
}

func handleForceGc(forceFreeOSMemory bool) {
	go func() {
		log.Infoln("[APP] Request force GC, forceFreeOSMemory=%t", forceFreeOSMemory)
		runtime.GC()
		if forceFreeOSMemory {
			debug.FreeOSMemory()
		}
	}()
}

func handleShutdown() bool {
	stopListeners()
	executor.Shutdown()
	runtime.GC()
	debug.FreeOSMemory()
	isInit = false
	return true
}

func handleValidateConfig(params *ValidateConfigParams) string {
	ageMutex.Lock()
	defer ageMutex.Unlock()

	if params.AgeSecretKey != "" {
		age.SetGlobalSecretKeys(params.AgeSecretKey)
		defer age.SetGlobalSecretKeys()
	}

	_, err := config.Parse([]byte(params.Data))
	if err != nil {
		return err.Error()
	}
	return ""
}

func handleDecryptAgeConfig(params *DecryptAgeConfigParams) string {
	ageMutex.Lock()
	defer ageMutex.Unlock()

	decrypted, err := age.DecryptBytes([]byte(params.Data), params.AgeSecretKey)
	if err != nil {
		return ""
	}
	return string(decrypted)
}

func handleGetProxies() map[string]constant.Proxy {
	runLock.Lock()
	defer runLock.Unlock()
	if !isInit {
		return make(map[string]constant.Proxy)
	}
	return tunnel.Proxies()
}

func handleChangeProxy(data string, fn func(string string)) {
	if !isInit {
		fn("core not initialized")
		return
	}
	runLock.Lock()
	go func() {
		defer runLock.Unlock()
		var params = &ChangeProxyParams{}
		err := json.Unmarshal([]byte(data), params)
		if err != nil {
			fn(err.Error())
			return
		}
		groupName := *params.GroupName
		proxyName := *params.ProxyName
		group, ok := tunnel.Proxies()[groupName]
		if !ok {
			fn("Not found group")
			return
		}
		adapterProxy := group.(*adapter.Proxy)
		selector, ok := adapterProxy.ProxyAdapter.(outboundgroup.SelectAble)
		if !ok {
			fn("Group is not selectable")
			return
		}
		if proxyName == "" {
			selector.ForceSet(proxyName)
		} else {
			err = selector.Set(proxyName)
		}
		if err != nil {
			fn(err.Error())
			return
		}

		fn("")
		return
	}()
}

func handleGetTraffic() string {
	up, down := statistic.DefaultManager.NowTraffic(state.CurrentState.OnlyStatisticsProxy)
	traffic := map[string]int64{
		"up":   up,
		"down": down,
	}
	data, err := json.Marshal(traffic)
	if err != nil {
		fmt.Println("Error:", err)
		return ""
	}
	return string(data)
}

func handleGetTotalTraffic() string {
	up, down := statistic.DefaultManager.TotalTraffic(state.CurrentState.OnlyStatisticsProxy)
	traffic := map[string]int64{
		"up":   up,
		"down": down,
	}
	data, err := json.Marshal(traffic)
	if err != nil {
		fmt.Println("Error:", err)
		return ""
	}
	return string(data)
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
}

func handleAsyncTestDelay(paramsString string, fn func(string)) {
	mBatch.Go(paramsString, func() (bool, error) {
		var params = &TestDelayParams{}
		err := json.Unmarshal([]byte(paramsString), params)
		if err != nil {
			fn("")
			return false, nil
		}

		expectedStatus, err := utils.NewUnsignedRanges[uint16]("")
		if err != nil {
			fn("")
			return false, nil
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond*time.Duration(params.Timeout))
		defer cancel()

		var proxy constant.Proxy
		var exist bool
		if proxy, exist = tunnel.Proxies()[params.ProxyName]; !exist {
			for _, provider := range tunnel.Providers() {
				for _, p := range provider.Proxies() {
					if p.Name() == params.ProxyName {
						proxy = p
						exist = true
						break
					}
				}
				if exist {
					break
				}
			}
		}

		delayData := &Delay{
			Name: params.ProxyName,
		}

		if proxy == nil {
			delayData.Value = -1
			data, _ := json.Marshal(delayData)
			fn(string(data))
			return false, nil
		}

		testUrl := constant.DefaultTestURL

		if params.TestUrl != "" {
			testUrl = params.TestUrl
		}
		delayData.Url = testUrl

		delay, err := proxy.URLTest(ctx, testUrl, expectedStatus)
		if err != nil || delay == 0 {
			delayData.Value = -1
			data, _ := json.Marshal(delayData)
			fn(string(data))
			return false, nil
		}

		delayData.Value = int32(delay)
		data, _ := json.Marshal(delayData)
		fn(string(data))
		return false, nil
	})
}

// speedTestURLToMetadata 将下载测速地址解析为出站连接所需的元数据。
// 逻辑与 adapter 包内 urlToMetadata 保持一致,复制到本包以避免修改 Clash.Meta 源码。
func speedTestURLToMetadata(rawURL string) (addr constant.Metadata, err error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return
	}

	port := u.Port()
	if port == "" {
		switch u.Scheme {
		case "https":
			port = "443"
		case "http":
			port = "80"
		default:
			err = fmt.Errorf("%s scheme not Support", rawURL)
			return
		}
	}

	err = addr.SetRemoteAddress(net.JoinHostPort(u.Hostname(), port))
	return
}

// speedTestCounter 统计已下载字节数,并按秒推送实时进度消息
type speedTestCounter struct {
	name       string
	url        string
	total      int64
	start      time.Time
	lastReport time.Time
}

func (c *speedTestCounter) Write(p []byte) (int, error) {
	c.total += int64(len(p))
	if now := time.Now(); now.Sub(c.lastReport) >= time.Second {
		elapsed := now.Sub(c.start).Seconds()
		sendMessage(Message{
			Type: SpeedTestMessage,
			Data: &SpeedTestProgress{
				Url:     c.url,
				Name:    c.name,
				Speed:   float64(c.total) / elapsed,
				Bytes:   c.total,
				Elapsed: int64(elapsed * 1000),
			},
		})
		c.lastReport = now
	}
	return len(p), nil
}

// handleAsyncSpeedTest 对指定节点执行下载带宽测试:
// 经节点出站连接下载测速文件,按固定时长(Timeout)统计字节流量,期间每秒推送实时进度。
// 不经过 adapter.URLTest,避免测速写入节点延迟历史。
func handleAsyncSpeedTest(paramsString string, fn func(string)) {
	mBatch.Go(paramsString, func() (bool, error) {
		var params = &SpeedTestParams{}
		err := json.Unmarshal([]byte(paramsString), params)
		if err != nil {
			fn("")
			return false, nil
		}

		result := &SpeedResult{
			Name: params.ProxyName,
			Url:  params.TestUrl,
		}
		finishWith := func(speed float64, bytes int64, duration int64) {
			result.Speed = speed
			result.Bytes = bytes
			result.Duration = duration
			data, _ := json.Marshal(result)
			fn(string(data))
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond*time.Duration(params.Timeout))
		defer cancel()

		var proxy constant.Proxy
		var exist bool
		if proxy, exist = tunnel.Proxies()[params.ProxyName]; !exist {
			for _, provider := range tunnel.Providers() {
				for _, p := range provider.Proxies() {
					if p.Name() == params.ProxyName {
						proxy = p
						exist = true
						break
					}
				}
				if exist {
					break
				}
			}
		}

		if proxy == nil || params.TestUrl == "" {
			finishWith(-1, 0, 0)
			return false, nil
		}

		addr, err := speedTestURLToMetadata(params.TestUrl)
		if err != nil {
			finishWith(-1, 0, 0)
			return false, nil
		}

		instance, err := proxy.DialContext(ctx, &addr)
		if err != nil {
			finishWith(-1, 0, 0)
			return false, nil
		}
		defer func() {
			_ = instance.Close()
		}()

		tlsConfig, err := ca.GetTLSConfig(ca.Option{})
		if err != nil {
			finishWith(-1, 0, 0)
			return false, nil
		}

		// 出站必须复用节点的拨号连接,禁止回退默认 Transport 绕过节点
		transport := &http.Transport{
			DialContext: func(context.Context, string, string) (net.Conn, error) {
				return instance, nil
			},
			MaxIdleConns:          100,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
			TLSClientConfig:       tlsConfig,
		}

		client := http.Client{
			Transport: transport,
		}
		defer client.CloseIdleConnections()

		start := time.Now()
		counter := &speedTestCounter{
			name:       params.ProxyName,
			url:        params.TestUrl,
			start:      start,
			lastReport: start,
		}
		// 分轮循环下载直到测试时长结束:下载源可能限制单次响应字节数(实测 Cloudflare
		// __down 对 100MB 请求经代理返回 403),小文件提前 EOF 后发起下一轮继续累计,
		// 保证任何尺寸限制的下载源都能测满整个时长
		for time.Since(start) < time.Millisecond*time.Duration(params.Timeout) {
			roundReq, err := http.NewRequest(http.MethodGet, params.TestUrl, nil)
			if err != nil {
				break
			}
			roundReq = roundReq.WithContext(ctx)
			roundReq.Header.Set("User-Agent", "Bettbox/1.0 SpeedTest")

			resp, err := client.Do(roundReq)
			if err != nil {
				// ctx 到期或连接中断:已有累计字节则按已完成部分结算
				break
			}
			if resp.StatusCode < 200 || resp.StatusCode >= 300 {
				_ = resp.Body.Close()
				// 首轮即异常按失败结算;后续轮次异常但已有数据则按已完成部分结算
				break
			}
			_, _ = io.Copy(counter, resp.Body)
			_ = resp.Body.Close()
		}

		elapsed := time.Since(start)
		if elapsed <= 0 || counter.total <= 0 {
			finishWith(-1, 0, elapsed.Milliseconds())
			return false, nil
		}
		finishWith(float64(counter.total)/elapsed.Seconds(), counter.total, elapsed.Milliseconds())
		return false, nil
	})
}

func handleGetConnections() string {
	runLock.Lock()
	defer runLock.Unlock()
	snapshot := statistic.DefaultManager.Snapshot()
	data, err := json.Marshal(snapshot)
	if err != nil {
		fmt.Println("Error:", err)
		return ""
	}
	return string(data)
}

func handleCloseConnections() bool {
	runLock.Lock()
	defer runLock.Unlock()
	closeConnections()
	return true
}

func closeConnections() {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		err := c.Close()
		if err != nil {
			return false
		}
		return true
	})
}

func handleResetConnections() bool {
	runLock.Lock()
	defer runLock.Unlock()
	resolver.ResetConnection()
	return true
}

func handleCloseConnection(connectionId string) bool {
	runLock.Lock()
	defer runLock.Unlock()
	c := statistic.DefaultManager.Get(connectionId)
	if c == nil {
		return false
	}
	_ = c.Close()
	return true
}

func handleGetExternalProviders() string {
	runLock.Lock()
	defer runLock.Unlock()
	if !isInit {
		return "[]"
	}
	externalProviders = getExternalProvidersRaw()
	eps := make([]ExternalProvider, 0)
	for _, p := range externalProviders {
		externalProvider, err := toExternalProvider(p)
		if err != nil {
			continue
		}
		eps = append(eps, *externalProvider)
	}
	sort.Sort(ExternalProviders(eps))
	data, err := json.Marshal(eps)
	if err != nil {
		return ""
	}
	return string(data)
}

func handleGetExternalProvider(externalProviderName string) string {
	runLock.Lock()
	defer runLock.Unlock()
	externalProvider, exist := externalProviders[externalProviderName]
	if !exist {
		return ""
	}
	e, err := toExternalProvider(externalProvider)
	if err != nil {
		return ""
	}
	data, err := json.Marshal(e)
	if err != nil {
		return ""
	}
	return string(data)
}

func handleUpdateGeoData(geoType string, geoName string, fn func(value string)) {
	go func() {
		path := constant.Path.Resolve(geoName)
		switch geoType {
		case "MMDB":
			err := updater.UpdateMMDBWithPath(path)
			if err != nil {
				fn(err.Error())
				return
			}
		case "ASN":
			err := updater.UpdateASNWithPath(path)
			if err != nil {
				fn(err.Error())
				return
			}
		case "GeoSite":
			err := updater.UpdateGeoSiteWithPath(path)
			if err != nil {
				fn(err.Error())
				return
			}
		}
		fn("")
	}()
}

func handleUpdateExternalProvider(providerName string, fn func(value string)) {
	go func() {
		externalProvider, exist := externalProviders[providerName]
		if !exist {
			fn("external provider is not exist")
			return
		}
		err := externalProvider.Update()
		if err != nil {
			fn(err.Error())
			return
		}
		fn("")
	}()
}

func handleSideLoadExternalProvider(providerName string, data []byte, fn func(value string)) {
	go func() {
		runLock.Lock()
		defer runLock.Unlock()
		externalProvider, exist := externalProviders[providerName]
		if !exist {
			fn("external provider is not exist")
			return
		}
		err := sideUpdateExternalProvider(externalProvider, data)
		if err != nil {
			fn(err.Error())
			return
		}
		fn("")
	}()
}

func handleParseExternalProviderContent(providerName string, fn func(value string)) {
	go func() {
		runLock.Lock()
		p, exist := getExternalProvidersRaw()[providerName]
		rawConfig := currentRawConfig
		runLock.Unlock()

		if !exist {
			fn("external provider does not exist")
			return
		}

		if p.VehicleType() == cp.Inline {
			buf, err := marshalInlineProviderContent(rawConfig, providerName)
			if err != nil {
				fn(err.Error())
				return
			}
			fn(string(buf))
			return
		}

		ep, err := toExternalProvider(p)
		if err != nil || ep.Path == "" {
			fn("provider path is empty")
			return
		}

		buf, err := os.ReadFile(ep.Path)
		if err != nil {
			fn(fmt.Sprintf("read file error: %v", err))
			return
		}

		if rp, ok := p.(cp.RuleProvider); ok {
			var out bytes.Buffer
			if err := rulesProvider.ConvertToMrs(buf, rp.Behavior(), cp.MrsRule, &out); err == nil {
				fn(out.String())
				return
			}
		}

		fn(string(buf))
	}()
}

func marshalInlineProviderContent(rawConfig *config.RawConfig, providerName string) ([]byte, error) {
	if rawConfig == nil {
		return nil, fmt.Errorf("provider content is empty")
	}

	rawProvider, exist := rawConfig.ProxyProvider[providerName]
	if !exist {
		return nil, fmt.Errorf("provider content is empty")
	}
	payload, exist := rawProvider["payload"]
	if !exist {
		return nil, fmt.Errorf("provider content is empty")
	}

	return yaml.Marshal(map[string]any{"proxies": payload})
}

func handleStartLog() {
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
	logSubscriber = log.Subscribe()
	go func() {
		for logData := range logSubscriber {
			if logData.LogLevel < log.Level() {
				continue
			}
			message := &Message{
				Type: LogMessage,
				Data: logData,
			}
			sendMessage(*message)
		}
	}()
}

func handleStopLog() {
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
}

func handleGetCountryCode(ip string, fn func(value string)) {
	go func() {
		runLock.Lock()
		defer runLock.Unlock()
		codes := mmdb.IPInstance().LookupCode(net.ParseIP(ip))
		if len(codes) == 0 {
			fn("")
			return
		}
		fn(codes[0])
	}()
}

func handleGetMemory(fn func(value string)) {
	go func() {
		fn(strconv.FormatUint(statistic.DefaultManager.Memory(), 10))
	}()
}

func handleGetMode() string {
	if !isInit {
		return ""
	}
	return tunnel.Mode().String()
}

func handleSetState(params string) {
	_ = json.Unmarshal([]byte(params), state.CurrentState)
}

func handleGetConfig(params *GetConfigParams) (*config.RawConfig, error) {
	ageMutex.Lock()
	defer ageMutex.Unlock()

	if params.AgeSecretKey != "" {
		age.SetGlobalSecretKeys(params.AgeSecretKey)
		defer age.SetGlobalSecretKeys()
	}

	bytes, err := readFile(params.Path)
	if err != nil {
		return nil, err
	}
	prof, err := config.UnmarshalRawConfig(bytes)
	if err != nil {
		return nil, err
	}
	return prof, nil
}

func handleFlushFakeIP() bool {
	if !isInit {
		return false
	}
	err := resolver.FlushFakeIP()
	if err != nil {
		log.Errorln("[APP] Flush FakeIP error: %v", err)
		return false
	}
	log.Infoln("[APP] FakeIP pool flushed")
	return true
}

func handleFlushDnsCache() {
	resolver.ClearCache()
	log.Infoln("[APP] DNS cache flushed")
}

func handleCrash() {
	panic("handle invoke crash")
}

func handleUpdateConfig(bytes []byte) string {
	var params = &UpdateParams{}
	err := json.Unmarshal(bytes, params)
	if err != nil {
		return err.Error()
	}
	updateConfig(params)
	return ""
}

func handleSetupConfig(bytes []byte) string {
	var params = defaultSetupParams()
	err := UnmarshalJson(bytes, params)
	if err != nil {
		log.Errorln("unmarshalRawConfig error %v", err)
		_ = setupConfig(defaultSetupParams())
		return err.Error()
	}
	clearSuspendedHealthChecks()
	clearSuspendedWireGuard()
	err = setupConfig(params)
	if err != nil {
		return err.Error()
	}
	return ""
}

func handleSuspend(suspended bool) bool {
	if !isInit {
		return false
	}
	if suspended {
		log.Infoln("[APP] Suspend mode enabled")
		tunnel.OnSuspend()
		pauseHealthChecks()
		pauseWireGuard()

		mihomoNtp.ReCreateNTPService("", 0, "", nil, false)

		statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
			_ = c.Close()
			return true
		})

		runtime.GC()
	} else {
		log.Infoln("[APP] Resume from suspend")
		tunnel.OnRunning()
		resumeHealthChecks()
		resumeWireGuard()

		runLock.Lock()
		cfg := currentConfig
		runLock.Unlock()
		if cfg != nil && cfg.NTP != nil && cfg.NTP.Enable {
			c := cfg.NTP
			mihomoNtp.ReCreateNTPService(
				net.JoinHostPort(c.Server, strconv.Itoa(c.Port)),
				time.Duration(c.Interval),
				c.DialerProxy,
				tunnel.Tunnel,
				c.WriteToSystem,
			)
		}
	}
	return true
}

func init() {
	adapter.UrlTestHook = func(url string, name string, delay uint16) {
		delayData := &Delay{
			Url:  url,
			Name: name,
		}
		if delay == 0 {
			delayData.Value = -1
		} else {
			delayData.Value = int32(delay)
		}
		sendMessage(Message{
			Type: DelayMessage,
			Data: delayData,
		})
	}
	statistic.DefaultRequestNotify = func(c statistic.Tracker) {
		sendMessage(Message{
			Type: RequestMessage,
			Data: c.Info(),
		})
	}
	executor.DefaultProviderLoadedHook = func(providerName string) {
		sendMessage(Message{
			Type: LoadedMessage,
			Data: providerName,
		})
	}
}
